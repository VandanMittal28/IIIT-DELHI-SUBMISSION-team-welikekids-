export type Organization = { id: string; name: string; college_id: string };

export type EventRecord = {
  id: string;
  title: string;
  category: string;
  status?: "draft" | "pending_approval" | "published" | "cancelled";
  organization_id: string;
  organization_name?: string;
  college_name?: string;
  starts_at?: string;
  ends_at?: string;
  price_minor?: number;
  currency?: string;
};

export type EventDraft = {
  organizationId: string;
  title: string;
  description: string;
  category: string;
  visibility: "public" | "college_only" | "organization_only";
  priceRupees: string;
  eligibility: string;
  registrationOpensAt: string;
  registrationClosesAt: string;
  startsAt: string;
  endsAt: string;
  capacity: string;
  waitlistEnabled: boolean;
};

export type RegistrationSummary = {
  edition_id: string;
  event_id: string;
  capacity: number;
  registered_count: number;
  waitlisted_count: number;
  cancelled_count: number;
};
