create view public.published_event_session_schedule
with (security_invoker=true) as
select session.id,session.edition_id,session.title,session.starts_at,session.ends_at,
       venue.id venue_id,venue.name venue_name,campus.id campus_id,campus.name campus_name
from public.event_sessions session
join public.event_editions edition on edition.id=session.edition_id
join public.events event on event.id=edition.event_id
left join public.venues venue on venue.id=session.venue_id
left join public.campuses campus on campus.id=venue.campus_id
where event.status='published';

create view public.edition_review_summary
with (security_invoker=true) as
select review.event_id,review.edition_id,count(*)::integer sample_size,avg(review.rating)::numeric(3,2) average_rating
from public.reviews review
join public.events event on event.id=review.event_id
where event.status='published'
group by review.event_id,review.edition_id;

grant select on public.published_event_session_schedule,public.edition_review_summary to anon,authenticated;
