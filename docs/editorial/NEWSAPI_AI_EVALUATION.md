# NewsAPI.ai Evaluation Source Policy

**Status:** Experimental evaluation only
**Reviewed:** 2026-08-09

NewsAPI.ai is being evaluated as an official API source for event discovery,
publisher metadata, clustering, and transient article-text analysis. It is not
yet approved as a production source adapter.

- **Owner:** Event Registry / NewsAPI.ai
- **Access method:** Authenticated JSON API
- **Endpoints:** `https://eventregistry.org/api/v1/`
- **Permitted experiment:** Retrieve recent event and article data using the
  registered trial account and evaluate it privately for editorial ranking.
- **Attribution:** Preserve the original publisher name and URL for every
  article used as evidence.
- **Raw-text retention:** In-memory for the ranking request; do not persist or
  commit article bodies during this experiment.
- **Rate and token limits:** Make sequential calls and stay within the account
  token allocation.
- **Publication:** This evaluation does not authorize redistribution of article
  bodies or production publication based on the API alone.
- **Production gate:** Review the subscribed plan and final contract terms,
  permitted uses, retention, and attribution before enabling production use.

NewsAPI.ai advertises full article content, event clustering, duplicate
detection, source metadata, and use for data analysis and machine learning. The
actual extraction completeness and vendor-generated categories remain
untrusted inputs and require validation.
