class Source < ApplicationRecord
  enum :source_type, {
    primary: "primary",
    licensed_reporting: "licensed_reporting",
    public_reporting: "public_reporting",
    discovery_only: "discovery_only"
  }, prefix: true, validate: true

  has_many :source_policies, dependent: :restrict_with_error
  has_many :collection_runs, dependent: :restrict_with_error
  has_many :source_documents, dependent: :restrict_with_error

  validates :name, :slug, :source_type, :owner_name, :canonical_url, presence: true
  validates :slug, uniqueness: true

  def approved_policy
    source_policies.approved.order(version: :desc).first
  end
end
