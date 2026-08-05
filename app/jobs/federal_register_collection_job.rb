class FederalRegisterCollectionJob < ApplicationJob
  queue_as :collection

  limits_concurrency to: 1, key: -> { "federal-register" }, duration: 30.minutes

  def perform(publication_date: Date.current)
    Collectors::FederalRegister.new.call(publication_date:)
  end
end
