create view public.my_attendance_history
with (security_invoker=true) as
select transition.id,transition.edition_id,event.id event_id,event.title,
       transition.action,transition.recorded_at
from public.attendance_transitions transition
join public.registrations registration on registration.id=transition.registration_id
join public.event_editions edition on edition.id=transition.edition_id
join public.events event on event.id=edition.event_id
where registration.user_id=(select auth.uid());

create view public.my_submitted_reviews
with (security_invoker=true) as
select review.id,review.event_id,review.edition_id,event.title,
       review.rating,review.body,review.created_at,review.updated_at
from public.reviews review
join public.events event on event.id=review.event_id
where review.user_id=(select auth.uid());

grant select on public.my_attendance_history,public.my_submitted_reviews to authenticated;
