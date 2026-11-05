# Modern CQRS and API contracts

> Profile skill `modern-cqrs-api-contracts`: Modern commands, queries, handlers, and HTTP API contracts. Load only when the helper's profile is modern.

Shipped baseline from the 3.6.0 brief; the Formula agent instructions in profiles-custom replace it (see
`profiles/README.md`). Applies only when `profile` reports `modern`.

- One handler per command or query, dispatched through `IDispatcher` as the sibling functions do. Commands change state;
  queries do not.
- Commands, queries, handlers, validators, and response models follow the folder and naming pattern of the nearest sibling
  feature. A dependency used by both commands and queries lives where the siblings keep shared dependencies, not inside
  one command's or query's folder (pre-PR scenario 5).
- Function layer: route, HTTP verb, authorization level, and OpenAPI attributes as siblings declare them. The function
  dispatches and maps the result; it does not re-validate, and it does not re-translate exceptions that the application
  layer and the exception middleware already handle (pre-PR scenarios 1 and 2).
- **Contracts:** for every changed request or response model write the before/after shape, nullability, and error shape,
  and check every consumer. Prefer additive changes. Never rename or remove a field a client reads without approval.
- Error responses keep the existing contract: field, message, and HTTP status as the middleware produces them today.
