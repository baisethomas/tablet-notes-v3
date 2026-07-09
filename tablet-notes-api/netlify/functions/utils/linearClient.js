class LinearClient {
  constructor({
    apiKey,
    authHeader,
    endpoint = 'https://api.linear.app/graphql',
    fetchImpl = fetch
  }) {
    if (!apiKey && !authHeader) {
      throw new Error('Linear API key or auth header is required');
    }

    this.authHeader = authHeader || apiKey;
    this.endpoint = endpoint;
    this.fetch = fetchImpl;
  }

  async createIssue(input) {
    const resolvedInput = {
      ...input,
      teamId: await this.resolveTeamId(input.teamId)
    };
    const query = `
      mutation IssueCreate($input: IssueCreateInput!) {
        issueCreate(input: $input) {
          success
          issue {
            id
            identifier
            title
            url
          }
        }
      }
    `;

    const data = await this.graphql(query, { input: resolvedInput });
    if (!data.issueCreate?.success) {
      throw new Error('Linear issueCreate did not return success');
    }

    return data.issueCreate.issue;
  }

  async resolveTeamId(teamIdOrKey) {
    if (!teamIdOrKey || isUuid(teamIdOrKey) || !isLikelyTeamKey(teamIdOrKey)) {
      return teamIdOrKey;
    }

    const query = `
      query Teams($query: String!) {
        teams(first: 50, filter: { or: [{ key: { eq: $query } }, { name: { eq: $query } }] }) {
          nodes {
            id
            key
            name
          }
        }
      }
    `;

    const data = await this.graphql(query, { query: teamIdOrKey });
    const normalizedQuery = String(teamIdOrKey).toLowerCase();
    const team = data.teams.nodes.find((candidate) =>
      candidate.key.toLowerCase() === normalizedQuery ||
      candidate.name.toLowerCase() === normalizedQuery
    );

    if (!team) {
      throw new Error(`Linear team not found: ${teamIdOrKey}`);
    }

    return team.id;
  }

  async graphql(query, variables) {
    const response = await this.fetch(this.endpoint, {
      method: 'POST',
      headers: {
        Authorization: this.authHeader,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ query, variables })
    });

    const body = await response.json().catch(async () => ({
      errors: [{ message: await response.text() }]
    }));

    if (!response.ok) {
      throw new Error(`Linear API request failed (${response.status}): ${JSON.stringify(body)}`);
    }

    if (body.errors?.length) {
      throw new Error(`Linear GraphQL error: ${body.errors.map((error) => error.message).join('; ')}`);
    }

    return body.data;
  }
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value || ''));
}

function isLikelyTeamKey(value) {
  return /^[A-Z]{2,10}$/.test(String(value || ''));
}

module.exports = {
  LinearClient
};
