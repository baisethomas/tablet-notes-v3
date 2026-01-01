# Security Implementation Guide

This document outlines the security measures implemented in the Tablet Notes API.

## Overview

The Tablet Notes API has been enhanced with comprehensive security measures to protect against common attacks and ensure production readiness for beta testing.

## Security Features Implemented

### 1. Rate Limiting

**Implementation**: Redis-based rate limiting with fallback to in-memory storage
**Configuration**: Different limits for different endpoint types

```javascript
// Rate limits per user
- General API: 60 requests/minute
- File uploads: 10 requests/hour  
- Transcription: 20 requests/hour
- Summarization: 50 requests/hour
- Bible API: 30 requests/minute

// Rate limits per IP (additional protection)
- All endpoints: 100 requests/minute per IP
```

**Setup**: 
1. Set `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` environment variables
2. If Redis is unavailable, system falls back to allowing all requests with warnings

### 2. Input Validation

**Implementation**: Joi-based schema validation with sanitization
**Features**:
- File type and size validation for uploads
- Text length limits and sanitization
- Request size limits (10MB max)
- Parameter validation and type checking

**File Upload Restrictions**:
- Maximum file size: 500MB
- Allowed audio types: MP3, WAV, M4A, AAC, OGG, WEBM, FLAC
- Filename character restrictions: alphanumeric, dots, underscores, hyphens only

### 3. CORS Configuration

**Implementation**: Environment-based origin control
**Configuration**:
```javascript
// Production origins
- https://tabletnotes.io
- https://www.tabletnotes.io  
- https://app.tabletnotes.io

// Development origins (when NODE_ENV=development)
- http://localhost:3000
- http://localhost:8080
- http://127.0.0.1:3000
- https://localhost:3000

// Preview deploys
- Automatic support for Netlify preview URLs
```

**Setup**: Set `ALLOWED_ORIGINS` environment variable with comma-separated list

### 4. Authentication & Authorization

**Implementation**: Supabase JWT verification with user isolation
**Features**:
- Bearer token validation on all endpoints
- User ID extraction from JWT
- Resource ownership verification (users can only access their own files)
- Automatic user context attachment to requests

### 5. Request Timeouts & Circuit Breakers

**Implementation**: Per-service circuit breakers with configurable timeouts
**Configuration**:
```javascript
// Timeouts
- General requests: 30 seconds
- File uploads: 5 minutes  
- Transcription: 10 minutes
- Summarization: 2 minutes

// Circuit Breakers (3 failures trigger 1-minute cooldown)
- AssemblyAI API
- OpenAI API
- Bible API
- Supabase Storage
```

### 6. Security Headers

**Implementation**: Comprehensive security headers on all responses
**Headers Applied**:
```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'; script-src 'none'; object-src 'none';
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

### 7. Structured Logging & Monitoring

**Implementation**: JSON-formatted logging with security event tracking
**Logged Events**:
- Authentication failures
- Rate limit violations
- Unauthorized access attempts
- Input validation failures
- API errors and performance metrics

**Log Levels**: ERROR, WARN, INFO, DEBUG (configurable via `LOG_LEVEL`)

## Environment Variables Required

### Production Environment
```bash
# Core Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
ASSEMBLYAI_API_KEY=your-assemblyai-key
OPENAI_API_KEY=your-openai-key
BIBLE_API_KEY=your-bible-api-key

# Security Configuration  
ALLOWED_ORIGINS=https://tabletnotes.io,https://www.tabletnotes.io
NODE_ENV=production
LOG_LEVEL=INFO

# Rate Limiting (Recommended for production)
UPSTASH_REDIS_REST_URL=https://your-redis.upstash.io
UPSTASH_REDIS_REST_TOKEN=your-redis-token
```

### Development Environment
```bash
# Add to production config:
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
NODE_ENV=development
LOG_LEVEL=DEBUG
```

## Security Best Practices Implemented

### 1. Defense in Depth
- Multiple layers of validation (rate limiting, auth, input validation)
- Circuit breakers prevent cascade failures
- Graceful degradation when services are unavailable

### 2. Least Privilege
- Users can only access their own resources
- Service-specific rate limits
- Minimal error information exposure

### 3. Input Sanitization
- All text inputs sanitized to prevent injection
- File uploads restricted by type and size
- Request size limits enforced

### 4. Error Handling
- Consistent error response format
- No sensitive information in error messages
- Proper HTTP status codes
- Security events logged for monitoring

### 5. Monitoring & Alerting
- Structured logging for security events
- Performance metrics tracking
- Rate limit violation monitoring
- Failed authentication tracking

## Testing Security Features

### 1. Rate Limiting Test
```bash
# Test rate limiting (should return 429 after limit)
for i in {1..70}; do
  curl -X POST https://your-api.netlify.app/.netlify/functions/bible-api \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"endpoint": "bibles"}'
done
```

### 2. Input Validation Test
```bash
# Test file size validation (should return 400)
curl -X POST https://your-api.netlify.app/.netlify/functions/generate-upload-url \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"fileName": "test.mp3", "fileSize": 600000000}' # 600MB - exceeds limit
```

### 3. Authentication Test
```bash
# Test missing auth (should return 401)
curl -X POST https://your-api.netlify.app/.netlify/functions/summarize \
  -H "Content-Type: application/json" \
  -d '{"text": "test"}'
```

### 4. CORS Test
```bash
# Test invalid origin (should be rejected)
curl -X POST https://your-api.netlify.app/.netlify/functions/bible-api \
  -H "Origin: https://malicious-site.com" \
  -H "Authorization: Bearer $TOKEN" \
  -v
```

## Monitoring & Alerts

### Key Metrics to Monitor
- Request rate and response times
- Error rates by endpoint
- Authentication failure rates
- Rate limit hit rates
- Circuit breaker activations

### Recommended Alerts
- Error rate > 5% for any endpoint
- Authentication failure rate > 10%
- Rate limit violations > 100/hour for any user
- Circuit breaker open for > 5 minutes
- Response time > 30 seconds

## Security Updates

This security implementation should be reviewed and updated regularly:

1. **Monthly**: Review rate limits and adjust based on usage patterns
2. **Quarterly**: Update dependencies and security headers
3. **Annually**: Full security audit and penetration testing

## Incident Response

In case of security incidents:

1. **Immediate**: Check logs for security events
2. **Short-term**: Temporarily tighten rate limits if needed
3. **Long-term**: Review and improve based on incident learnings

The structured logging will help identify the source and scope of any security issues.