# Fixing Error -7026: Sign in with Apple Configuration

## Critical Issue

Error `AKAuthenticationError Code=-7026` means **Sign in with Apple is not enabled** for your App ID in Apple Developer Portal.

## Immediate Fix Steps

### 1. Enable in Apple Developer Portal (REQUIRED)

**This is the most critical step and is likely the cause of your error.**

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click on **"Identifiers"**
3. Find your App ID: **`com.Augmego.FriendshipV2`**
4. Click to edit it
5. **Check the box for "Sign in with Apple"**
6. Click **"Save"**
7. **Wait 5-10 minutes** for changes to propagate

### 2. Add Capability in Xcode

1. Open your project in Xcode
2. Select the **"FriendshipV2"** target
3. Go to **"Signing & Capabilities"** tab
4. Click **"+ Capability"** button (top left)
5. Search for and add **"Sign in with Apple"**

This should automatically:
- Link your entitlements file
- Update the provisioning profile

### 3. Verify Entitlements File is Linked

1. In Xcode, select your target
2. Go to **"Build Settings"** tab
3. Search for **"Code Signing Entitlements"**
4. Make sure it shows: **`FriendshipV2/FriendshipV2.entitlements`**

If it's empty:
1. Go back to **"Signing & Capabilities"** tab
2. The entitlements file should appear automatically when you add the capability
3. If not, manually set it in Build Settings

### 4. Clean and Rebuild

```bash
# In Xcode:
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Product → Build (Cmd+B)
```

### 5. Test on Physical Device

**IMPORTANT**: Sign in with Apple has known issues in the iOS Simulator. You **MUST** test on a physical device.

## Verification Checklist

- [ ] App ID has "Sign in with Apple" enabled in Apple Developer Portal
- [ ] Capability added in Xcode (Signing & Capabilities tab)
- [ ] Entitlements file includes `com.apple.developer.applesignin`
- [ ] Entitlements file is linked in Build Settings
- [ ] Provisioning profile includes the capability
- [ ] Waited 5-10 minutes after enabling in Developer Portal
- [ ] Cleaned build folder and rebuilt
- [ ] Testing on a **physical device** (not simulator)

## Common Mistakes

1. **Only adding capability in Xcode** - You MUST also enable it in Apple Developer Portal
2. **Not waiting for propagation** - Changes in Developer Portal take 5-10 minutes
3. **Testing in simulator** - Use a physical device
4. **Wrong bundle ID** - Make sure it matches exactly: `com.Augmego.FriendshipV2`

## Still Not Working?

1. **Check provisioning profile**:
   - Xcode → Preferences → Accounts
   - Select your team
   - Click "Download Manual Profiles"
   - Or regenerate in Developer Portal

2. **Verify bundle ID matches**:
   - Xcode: Target → General → Bundle Identifier
   - Developer Portal: App ID identifier
   - Must match exactly

3. **Check team membership**:
   - Ensure you're a member of the development team
   - Team ID: `5TPDVDYM3M`

4. **Try manual provisioning**:
   - In Xcode, switch to "Manual" signing temporarily
   - Select a provisioning profile that includes Sign in with Apple
   - Switch back to "Automatic"

## Error Code Reference

- **-7026**: Sign in with Apple not configured (App ID doesn't have capability)
- **1000**: Unknown error (usually configuration issue)
- **1001**: User canceled
- **1002**: Authentication failed

The -7026 error specifically means the App ID in Apple Developer Portal doesn't have Sign in with Apple enabled. This is the #1 cause of this error.

