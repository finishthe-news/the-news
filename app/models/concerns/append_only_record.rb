module AppendOnlyRecord
  extend ActiveSupport::Concern

  included do
    before_update :reject_append_only_update
    before_destroy :reject_append_only_destroy
  end

  private

  def reject_append_only_update
    errors.add(:base, "record is append-only")
    throw :abort
  end

  def reject_append_only_destroy
    errors.add(:base, "record is append-only")
    throw :abort
  end
end
