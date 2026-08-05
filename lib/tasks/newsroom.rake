namespace :newsroom do
  namespace :collect do
    desc "Collect Federal Register documents for DATE (YYYY-MM-DD, defaults to today)"
    task federal_register: :environment do
      date = Date.iso8601(ENV.fetch("DATE", Date.current.iso8601))
      per_page = Integer(ENV.fetch("PER_PAGE", "100"), 10)
      run = Collectors::FederalRegister.new.call(
        publication_date: date,
        per_page: per_page
      )

      puts({
        run_id: run.id,
        status: run.status,
        documents_seen: run.documents_seen,
        documents_created: run.documents_created,
        snapshots_created: run.snapshots_created
      }.to_json)
    end
  end
end
