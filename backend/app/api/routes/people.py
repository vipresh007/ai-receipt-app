"""People you split with outside groups: balances, payments, invites
(docs/SPLITS.md)."""

from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db import get_session
from app.models import Person, PersonPayment, User
from app.schemas.split import (
    PersonDetailOut,
    PersonIn,
    PersonOut,
    PersonPatch,
    PersonPaymentIn,
)
from app.services import people_store, split_store
from app.services.mailer import Mailer, get_mailer

router = APIRouter()


@router.get("", response_model=list[PersonOut])
async def list_people(
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[PersonOut]:
    people = await session.scalars(
        select(Person).where(Person.owner_user_id == user.id).order_by(Person.display_name)
    )
    return [await people_store.person_out(session, user, p) for p in people]


@router.post("", response_model=PersonDetailOut, status_code=status.HTTP_201_CREATED)
async def add_person(
    data: PersonIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    mailer: Mailer | None = Depends(get_mailer),
) -> PersonDetailOut:
    person = Person(
        owner_user_id=user.id,
        display_name=data.name.strip()[:120],
        email=people_store.clean_email(data.email),
        invite_token=split_store.new_token(),
    )
    session.add(person)
    # Saved even if the invite below can't go out (they can share the link).
    await session.commit()
    if data.send_invite:
        await _send_invite(session, user, person, mailer)
        await session.commit()
    return await people_store.person_out(session, user, person, detail=True)


@router.get("/{person_id}", response_model=PersonDetailOut)
async def get_person(
    person_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PersonDetailOut:
    person = await people_store.require_person(session, person_id, user)
    return await people_store.person_out(session, user, person, detail=True)


@router.patch("/{person_id}", response_model=PersonDetailOut)
async def edit_person(
    person_id: UUID,
    data: PersonPatch,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PersonDetailOut:
    person = await people_store.require_person(session, person_id, user)
    if data.name is not None:
        person.display_name = data.name.strip()[:120]
    if data.email is not None:
        email = people_store.clean_email(data.email)
        if email != person.email:
            person.email = email
            person.invited_at = None  # a new address can be invited straight away
    await session.commit()
    return await people_store.person_out(session, user, person, detail=True)


@router.delete("/{person_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_person(
    person_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    person = await people_store.require_person(session, person_id, user)
    await people_store.delete_person(session, person)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{person_id}/invite", response_model=PersonDetailOut)
async def invite_person(
    person_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    mailer: Mailer | None = Depends(get_mailer),
) -> PersonDetailOut:
    """Email them their invite link."""
    person = await people_store.require_person(session, person_id, user)
    await _send_invite(session, user, person, mailer)
    await session.commit()
    return await people_store.person_out(session, user, person, detail=True)


@router.post(
    "/{person_id}/payments", response_model=PersonDetailOut, status_code=status.HTTP_201_CREATED
)
async def add_payment(
    person_id: UUID,
    data: PersonPaymentIn,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PersonDetailOut:
    """Record money that changed hands ("Sam paid me $40")."""
    person = await people_store.require_person(session, person_id, user)
    amount = split_store._money(data.amount, "amount")
    if amount == 0:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Enter an amount.")
    session.add(
        PersonPayment(
            owner_user_id=user.id,
            person_id=person.id,
            from_owner=data.you_paid,
            amount=amount,
            note=data.note.strip(),
        )
    )
    await session.commit()
    return await people_store.person_out(session, user, person, detail=True)


@router.delete("/{person_id}/payments/{payment_id}", response_model=PersonDetailOut)
async def delete_payment(
    person_id: UUID,
    payment_id: UUID,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PersonDetailOut:
    person = await people_store.require_person(session, person_id, user)
    payment = await session.get(PersonPayment, payment_id)
    if payment is None or payment.person_id != person.id or payment.owner_user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Payment not found.")
    await session.delete(payment)
    await session.commit()
    return await people_store.person_out(session, user, person, detail=True)


@router.post("/claim/{invite_token}", response_model=PersonDetailOut)
async def claim_invite(
    invite_token: str,
    user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PersonDetailOut:
    """Accept an invite: you see what you share with whoever sent it. Returns
    your person for them."""
    person = await session.scalar(select(Person).where(Person.invite_token == invite_token))
    if person is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "This invite link isn't valid any more.")
    mirror = await people_store.claim(session, person, user)
    await session.commit()
    return await people_store.person_out(session, user, mirror, detail=True)


async def _send_invite(
    session: AsyncSession, user: User, person: Person, mailer: Mailer | None
) -> None:
    if mailer is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Email invites aren't available right now. Share the link instead.",
        )
    if not person.email:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "Add their email first.")
    if person.user_id is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "They've already joined.")
    await people_store.check_invite_allowed(session, person)
    summary = await people_store.person_out(session, user, person)
    message = people_store.invite_email(
        split_store.display_name_for(user), person, Decimal(summary.balance), summary.currency
    )
    try:
        await mailer.send(to=person.email, **message)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Couldn't send the email. Share the link instead."
        ) from exc
    person.invited_at = datetime.now(UTC)
