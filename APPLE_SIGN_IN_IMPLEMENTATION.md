# Sign in with Apple Implementation

## Overview

This document describes the minimal, production-ready Sign in with Apple implementation for iOS (SwiftUI) and Next.js backend.

## Architecture

### iOS Side (`AuthService.swift`)

- **Sign in with Apple**: Uses `ASAuthorizationAppleIDProvider` to request `.email` and `.fullName` scopes
- **Silent Login**: Checks credential state on app launch using `getCredentialState(forUserID:)`
- **Token Storage**: Stores session token and Apple user ID in `UserDefaults` (consider Keychain for production)
- **Backend Communication**: Sends `userId` and `identityToken` to `POST /api/auth/apple`

### Next.js Backend

- **API Route**: `/api/auth/apple` (POST)
- **JWT Verification**: Verifies Apple identity tokens using Apple's JWKS (public keys)
- **User Management**: Upserts users in MongoDB with Apple ID and email
- **Session Tokens**: Returns JWT access and refresh tokens

## Files Created/Modified

### iOS
- `FriendshipV2/AuthService.swift` - Complete rewrite with silent login support
- `FriendshipV2/LoginView.swift` - Updated to use new API
- `FriendshipV2/FriendshipV2App.swift` - Added silent login on app launch

### Next.js
- `next-frontend/src/lib/apple-jwt-verifier.ts` - Apple JWT verification utility with JWKS
- `next-frontend/src/app/api/auth/apple/route.ts` - Main authentication endpoint

## API Endpoints

### POST `/api/auth/apple`

**Request:**
```json
{
  "userId": "001234.567890abcdef.1234",
  "identityToken": "eyJraWQiOiJlWGF1bm1..."
}
```

**Success Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "507f1f77bcf86cd799439011",
    "email": "user@example.com",
    "displayName": "John Doe"
  }
}
```

**Error Response (400/401/500):**
```json
{
  "error": "Token verification failed: Token has expired"
}
```

## iOS Usage

### Sign In Flow

```swift
// Initiate sign in
auth.signInWithApple()

// Check authentication state
if auth.isAuthenticated {
    // User is authenticated
}

// Silent login on app launch (automatic)
// Checks credential state and validates session
```

### Silent Login

The app automatically attempts silent login on launch:

1. Checks for stored Apple user ID
2. Verifies credential state with Apple
3. If `.authorized`, validates session token
4. Updates `isAuthenticated` state

## Security Considerations

### Production Recommendations

1. **Token Storage**: Replace `UserDefaults` with Keychain for secure token storage
2. **Token Validation**: Add backend token validation endpoint for silent login
3. **Error Handling**: Implement user-facing error messages
4. **Rate Limiting**: Add rate limiting to the API endpoint
5. **Logging**: Add structured logging for security events

### Apple JWT Verification

- Tokens are verified using Apple's public keys (JWKS)
- JWKS are cached for 1 hour to reduce API calls
- Token expiration and signature are validated
- Issuer and audience validation (if client ID provided)

## Testing

### Test Cases

1. **First-time sign in**: User grants email and full name
2. **Subsequent sign in**: User may not provide email again
3. **Silent login**: App launches with valid session
4. **Revoked authorization**: User revokes Apple sign in
5. **Token expiration**: Handle expired tokens gracefully

### Example Test Flow

```swift
// 1. Sign in
auth.signInWithApple()

// 2. Wait for authentication
// (handled via delegate)

// 3. Verify state
assert(auth.isAuthenticated == true)

// 4. Test silent login
let success = await auth.attemptSilentSignIn()
assert(success == true)
```

## Environment Variables

No additional environment variables required. The Apple JWT verifier uses Apple's public JWKS endpoint.

## Error Handling

### iOS Errors

- `AuthError.invalidResponse`: Server returned invalid response
- `AuthError.backendError`: Backend returned error with status code

### Backend Errors

- `400`: Missing or invalid request body
- `401`: Token verification failed
- `500`: Internal server error

## Next Steps

1. Add Keychain storage for tokens
2. Implement token refresh flow
3. Add user profile management
4. Add logout functionality
5. Add error UI feedback

