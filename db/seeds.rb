federal_register = Source.find_or_initialize_by(slug: "federal-register")
federal_register.assign_attributes(
  name: "Federal Register",
  source_type: "primary",
  owner_name: "Office of the Federal Register and U.S. Government Publishing Office",
  canonical_url: "https://www.federalregister.gov/",
  active: true,
  metadata: {
    "official_edition_url" => "https://www.govinfo.gov/app/collection/FR",
    "country" => "US"
  }
)
federal_register.save!

policy_attributes = {
  "access_method" => "official_json_api",
  "endpoint_url" => "https://www.federalregister.gov/api/v1/documents.json",
  "terms_url" => "https://www.federalregister.gov/policy/legal-status",
  "robots_url" => "https://www.federalregister.gov/robots.txt",
  "requests_per_minute" => 60,
  "max_concurrency" => 1,
  "retention_days" => 365,
  "allowed_uses" => [ "event_discovery", "claim_evidence", "source_linking" ],
  "attribution_requirements" => "Name the issuing agency and link the Federal Register document. Use the linked GovInfo PDF for legal verification.",
  "notes" => "FederalRegister.gov is an informational XML rendition. The linked GovInfo PDF is the official electronic edition."
}

policy = federal_register.source_policies.find_or_initialize_by(version: 1)
if policy.new_record?
  policy.assign_attributes(
    policy_attributes.merge(
      "status" => "approved",
      "reviewed_by" => "Robert Ritz",
      "reviewed_at" => Time.current,
      "effective_from" => Time.current,
      "content_hash" => CanonicalJson.sha256(policy_attributes)
    )
  )
  policy.save!
end
