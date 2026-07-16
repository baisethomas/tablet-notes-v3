function parseSupportInboxRoutes(value) {
  if (!value) {
    throw new Error('SUPPORT_INBOX_ROUTES is required');
  }

  let parsed;
  try {
    parsed = JSON.parse(value);
  } catch (error) {
    throw new Error('SUPPORT_INBOX_ROUTES must be valid JSON');
  }

  if (!isPlainObject(parsed) || Object.keys(parsed).length === 0) {
    throw new Error('SUPPORT_INBOX_ROUTES must contain at least one mailbox route');
  }

  return Object.fromEntries(Object.entries(parsed).map(([mailboxId, route]) => {
    if (!/^\d+$/.test(mailboxId)) {
      throw new Error(`Help Scout mailbox id must be numeric: ${mailboxId}`);
    }

    if (!isPlainObject(route)) {
      throw new Error(`Support inbox route ${mailboxId} must be an object`);
    }

    const productName = requiredString(route.productName, `Support inbox route ${mailboxId} productName is required`);
    const linearTeamId = requiredString(route.linearTeamId, `Support inbox route ${mailboxId} linearTeamId is required`);
    const agentGuidance = requiredString(route.agentGuidance, `Support inbox route ${mailboxId} agentGuidance is required`);

    return [mailboxId, {
      productName,
      supportSignature: optionalString(route.supportSignature) || `${productName} Support`,
      agentGuidance,
      linearTeamId,
      ...(optionalString(route.linearProjectId) ? { linearProjectId: route.linearProjectId.trim() } : {}),
      ...(optionalString(route.linearAssigneeId) ? { linearAssigneeId: route.linearAssigneeId.trim() } : {}),
      linearLabelIds: normalizeStringArray(route.linearLabelIds, mailboxId)
    }];
  }));
}

function requiredString(value, message) {
  const normalized = optionalString(value);
  if (!normalized) {
    throw new Error(message);
  }
  return normalized;
}

function optionalString(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function normalizeStringArray(value, mailboxId) {
  if (value === undefined) {
    return [];
  }

  if (!Array.isArray(value) || value.some((item) => !optionalString(item))) {
    throw new Error(`Support inbox route ${mailboxId} linearLabelIds must be an array of strings`);
  }

  return Array.from(new Set(value.map((item) => item.trim())));
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

module.exports = {
  parseSupportInboxRoutes
};
