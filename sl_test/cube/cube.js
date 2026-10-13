// Cube configuration for the sl_test SEO semantic layer.
// Secrets and connection details come from the environment only (CUBEJS_API_SECRET,
// CUBEJS_DB_*); nothing secret is stored in this repository.

// Collect every cube/view name a query touches, including nested and/or filters.
function membersOf(query) {
  const out = [];
  const walk = (f) => {
    if (!f) return;
    if (f.member) out.push(f.member);
    if (f.dimension) out.push(f.dimension);
    (f.and || []).forEach(walk);
    (f.or || []).forEach(walk);
  };
  (query.measures || []).forEach((m) => out.push(m));
  (query.dimensions || []).forEach((d) => out.push(d));
  (query.segments || []).forEach((s) => out.push(s));
  (query.timeDimensions || []).forEach((t) => out.push(t.dimension));
  (query.filters || []).forEach(walk);
  (query.order && Array.isArray(query.order) ? query.order : []).forEach((o) => out.push(o[0]));
  return out;
}

module.exports = {
  // Row-level isolation. The token must carry customer_id (string) and project_ids
  // (non-empty array). Every view in the query is filtered to those values, and a
  // filter the caller adds for another project is ANDed with ours, so it returns nothing.
  queryRewrite: (query, { securityContext }) => {
    const ctx = securityContext || {};
    const customerId = ctx.customer_id;
    const projectIds = ctx.project_ids;
    if (typeof customerId !== 'string' || !customerId ||
        !Array.isArray(projectIds) || projectIds.length === 0 ||
        !projectIds.every((p) => typeof p === 'string' && p)) {
      throw new Error('Access denied: the token must carry customer_id and project_ids.');
    }
    query.filters = query.filters || [];
    const views = new Set(membersOf(query).map((m) => String(m).split('.')[0]));
    views.forEach((v) => {
      query.filters.push({ member: `${v}.project_id`, operator: 'equals', values: projectIds });
      query.filters.push({ member: `${v}.customer_id`, operator: 'equals', values: [customerId] });
    });
    return query;
  },

  // One shared refresh context for the rollups. Rollups are shared across projects
  // (project_id is a rollup dimension); there is no per-project app id or rollup.
  scheduledRefreshContexts: () => [
    { securityContext: { customer_id: 'cust_predicta', project_ids: ['proj_pa'] } },
  ],
};
