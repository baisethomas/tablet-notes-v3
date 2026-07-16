class HelpScoutClient {
  constructor({
    appId,
    appSecret,
    baseUrl = 'https://api.helpscout.net/v2',
    fetchImpl = fetch
  }) {
    if (!appId || !appSecret) {
      throw new Error('Help Scout app id and app secret are required');
    }

    this.appId = appId;
    this.appSecret = appSecret;
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.fetch = fetchImpl;
    this.accessToken = null;
    this.tokenExpiresAt = 0;
  }

  async getConversation(conversationId) {
    return this.request(`/conversations/${conversationId}?embed=threads`);
  }

  async createDraftReply(conversationId, input) {
    if (!input?.customer?.id) {
      throw new Error('Help Scout customer id is required to create a draft reply');
    }

    return this.request(`/conversations/${conversationId}/reply`, {
      method: 'POST',
      body: {
        customer: { id: input.customer.id },
        text: input.text,
        draft: true,
        ...(input.status ? { status: input.status } : {})
      }
    });
  }

  async createNote(conversationId, input) {
    return this.request(`/conversations/${conversationId}/notes`, {
      method: 'POST',
      body: {
        text: input.text
      }
    });
  }

  async request(path, options = {}, retryOnUnauthorized = true) {
    const token = await this.getAccessToken();
    const response = await this.fetch(`${this.baseUrl}${path}`, {
      method: options.method || 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      ...(options.body ? { body: JSON.stringify(options.body) } : {})
    });

    if (response.status === 401 && retryOnUnauthorized) {
      this.accessToken = null;
      this.tokenExpiresAt = 0;
      return this.request(path, options, false);
    }

    if (!response.ok) {
      throw new Error(`Help Scout API request failed (${response.status}): ${await response.text()}`);
    }

    if (response.status === 204 || response.status === 201) {
      return {
        id: response.headers.get('Resource-Id') || response.headers.get('resource-id') || null
      };
    }

    return response.json();
  }

  async getAccessToken() {
    if (this.accessToken && Date.now() < this.tokenExpiresAt) {
      return this.accessToken;
    }

    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: this.appId,
      client_secret: this.appSecret
    });

    const response = await this.fetch(`${this.baseUrl}/oauth2/token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body
    });

    if (!response.ok) {
      throw new Error(`Help Scout token request failed (${response.status}): ${await response.text()}`);
    }

    const data = await response.json();
    this.accessToken = data.access_token;
    this.tokenExpiresAt = Date.now() + Math.max(0, (data.expires_in || 3600) - 300) * 1000;
    return this.accessToken;
  }
}

module.exports = {
  HelpScoutClient
};
