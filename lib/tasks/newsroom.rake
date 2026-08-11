namespace :newsroom do
  namespace :sources do
    desc "Synchronize source manifests into inactive sources and draft policies"
    task sync: :environment do
      results = Collectors::Calibre::SourceSynchronizer.new.call
      puts JSON.pretty_generate(results.map do |result|
        {
          slug: result.source.slug,
          active: result.source.active?,
          policy_version: result.policy.version,
          policy_status: result.policy.status,
          policy_created: result.policy_created
        }
      end)
    end
  end

  namespace :collect do
    desc "Collect one approved Calibre source for the current hour"
    task calibre: :environment do
      slug = ENV.fetch("SOURCE")
      slot_at = Time.iso8601(ENV.fetch("SLOT_AT", Time.current.beginning_of_hour.iso8601))
      cycle, created = NewsCollectionCycle.begin!(slot_at:, source_slugs: [ slug ])
      if created
        cycle.mark_running!
        NewsSourceCollectionJob.perform_now(
          slug,
          slot_at: slot_at.iso8601,
          cycle_id: cycle.id
        )
      end

      slot = Source.find_by!(slug:).news_collection_slots.find_by!(slot_at: slot_at.beginning_of_hour)
      puts({
        source: slug,
        slot_at: slot.slot_at.iso8601,
        status: slot.status,
        attempts: slot.attempts,
        collection_run_id: slot.collection_run_id
      }.to_json)
    end

    desc "Report whether the latest hourly collection window passes its soak gates"
    task soak_report: :environment do
      hours = Integer(ENV.fetch("HOURS", Collectors::Calibre::SoakReport::DEFAULT_HOURS.to_s), 10)
      ending_slot = Time.iso8601(ENV.fetch("ENDING_SLOT", Time.current.beginning_of_hour.iso8601))
      report = Collectors::Calibre::SoakReport.new(hours:).call(ending_slot:)

      puts JSON.pretty_generate(report)
      abort "collection soak has unresolved issues" unless report.fetch("passed")
    end

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

    desc "Discover recent NewsAPI.ai event clusters"
    task newsapi_events: :environment do
      end_date = Date.iso8601(ENV.fetch("END_DATE", Date.current.iso8601))
      start_date = Date.iso8601(ENV.fetch("START_DATE", (end_date - 2.days).iso8601))
      count = Integer(ENV.fetch("COUNT", "50"), 10)
      min_articles = Integer(ENV.fetch("MIN_ARTICLES", "5"), 10)
      client = NewsapiAi::Client.new(api_key: ENV.fetch("NEWSAPI_AI_KEY"))
      result = NewsapiAi::DiscoveryCollector.new(client:).call(
        start_date:,
        end_date:,
        count:,
        min_articles:
      )

      puts JSON.pretty_generate(result)
    end
  end

  namespace :ranking do
    desc "Build and score one NewsAPI.ai event dossier"
    task test: :environment do
      event_uri = ENV.fetch("EVENT_URI")
      model = ENV.fetch("MODEL", EditorialRanking::OpenRouterScorer::DEFAULT_MODEL)
      provider_route = ENV.fetch("PROVIDER_ROUTE", EditorialRanking::OpenRouterScorer::DEFAULT_PROVIDER_ROUTE)
      newsapi_client = NewsapiAi::Client.new(api_key: ENV.fetch("NEWSAPI_AI_KEY"))
      dossier = EditorialRanking::ClusterDossier.new(client: newsapi_client).call(event_uri:)
      prompt = EditorialRanking::Prompt.render(dossier)
      scorer = EditorialRanking::OpenRouterScorer.new(
        api_key: ENV.fetch("OPENROUTER_API_KEY"),
        model:,
        provider_route:,
        reasoning: EditorialRanking::OpenRouterScorer::DEFAULT_REASONING
      )
      result = scorer.call(prompt)

      puts EditorialRanking::Prompt.render(dossier, include_bodies: false)
      puts JSON.pretty_generate(
        "model" => result.model,
        "provider" => result.provider,
        "usage" => result.usage,
        "score" => result.score,
        "prompt_characters" => prompt.length,
        "evidence_articles" => dossier.fetch("evidence").length
      )
    end
  end
end
