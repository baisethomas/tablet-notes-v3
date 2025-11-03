# App Store Connect - In-App Purchase Setup Guide

## 📱 TabletNotes Subscription Configuration

This guide walks you through setting up In-App Purchases in App Store Connect for TabletNotes.

---

## ✅ Prerequisites

Before you start:
- [ ] Apple Developer Account ($99/year)
- [ ] App created in App Store Connect
- [ ] Bundle ID: `com.tabletnotes` (or your actual bundle ID)
- [ ] Signed Paid Applications Agreement in App Store Connect

---

## 🎯 Step 1: Sign Paid Applications Agreement

1. Go to https://appstoreconnect.apple.com
2. Click **Agreements, Tax, and Banking**
3. Find **Paid Applications** agreement
4. Click **Request** (if not already signed)
5. Fill out:
   - Contact Info
   - Bank Account Info (for receiving payments)
   - Tax Forms (W-9 for US, W-8 for international)
6. Submit and wait for approval (usually 24-48 hours)

**⚠️ You cannot test IAP without signing this agreement!**

---

## 🎯 Step 2: Create In-App Purchase Products

### Navigate to In-App Purchases

1. Go to https://appstoreconnect.apple.com
2. Select **My Apps** → **TabletNotes**
3. Click **In-App Purchases** in the left sidebar
4. Click the **+** button to create a new product

---

### Product 1: Premium Monthly

**Select Type:** Auto-Renewable Subscription

#### Reference Information
- **Reference Name:** `TabletNotes Premium (Monthly)`
- **Product ID:** `com.tabletnotes.premium.monthly`

**⚠️ IMPORTANT:** Product ID must EXACTLY match the code:
```swift
// From Subscription.swift line 214
productId: "com.tabletnotes.premium.monthly"
```

#### Subscription Group
- **Group Name:** `Premium Subscriptions`
- **Create new group** if you don't have one

#### Subscription Duration
- **Duration:** 1 Month

#### Subscription Price
- **Price:** $9.99 USD (Tier 10)
- Apple automatically sets prices for other countries

#### Localization (English - US)
- **Subscription Display Name:** `Premium Monthly`
- **Description:** `Unlimited sermon recordings with AI transcription and summaries. Billed monthly.`

#### Promotional Image (Optional)
- Size: 1024x1024px
- Skip for now, add later

#### Review Information
- **Screenshot:** Upload a screenshot of your subscription screen
- **Review Notes:** `Monthly subscription for premium features including unlimited recordings, AI transcription, and cloud sync.`

**Click Save**

---

### Product 2: Premium Annual

**Select Type:** Auto-Renewable Subscription

#### Reference Information
- **Reference Name:** `TabletNotes Premium (Annual)`
- **Product ID:** `com.tabletnotes.premium.annual`

**⚠️ IMPORTANT:** Product ID must EXACTLY match:
```swift
// From Subscription.swift line 225
productId: "com.tabletnotes.premium.annual"
```

#### Subscription Group
- **Use existing group:** `Premium Subscriptions`

#### Subscription Duration
- **Duration:** 1 Year

#### Subscription Price
- **Price:** $79.99 USD (Tier 80)

#### Localization (English - US)
- **Subscription Display Name:** `Premium Annual`
- **Description:** `Unlimited sermon recordings with AI transcription and summaries. Save 33% with annual billing.`

#### Review Information
- **Screenshot:** Upload a screenshot showing annual plan
- **Review Notes:** `Annual subscription for premium features. Saves $40/year compared to monthly plan.`

**Click Save**

---

## 🎯 Step 3: Configure Subscription Group Settings

1. Click on **Premium Subscriptions** group
2. Configure group settings:

### Subscription Group Display Name
- **Name:** `Premium`

### App Store Promotion (Optional)
- **Promotional Order:**
  1. Premium Annual (promote this first - better value)
  2. Premium Monthly

### App Store Localization
- Add descriptions for other languages if needed

**Click Save**

---

## 🎯 Step 4: Add Test Accounts (Sandbox Testing)

### Create Sandbox Testers

1. Go to **Users and Access** in App Store Connect
2. Click **Sandbox** tab
3. Click **+** to add tester
4. Fill out:
   - **Email:** Use a unique email (e.g., `test1@yourdomain.com`)
   - **Password:** Create a password you'll remember
   - **First/Last Name:** Test User
   - **Country:** United States
   - **App Store Territory:** United States

5. Create 2-3 test accounts for different scenarios

**⚠️ NEVER use your real Apple ID for sandbox testing!**

---

## 🎯 Step 5: Test In-App Purchases (Sandbox)

### On Your iPhone

1. **Sign out of App Store:**
   - Settings → Your Name → Media & Purchases → Sign Out
   - **Don't sign out of iCloud**, just Media & Purchases

2. **Install your app from Xcode:**
   - Build and run on your device
   - App must be signed with your dev certificate

3. **Attempt to purchase:**
   - Open TabletNotes
   - Navigate to subscription screen
   - Tap "Premium Monthly" or "Premium Annual"

4. **Sign in when prompted:**
   - Use your sandbox test account
   - **NOT your real Apple ID!**

5. **Complete purchase:**
   - Confirm purchase (you won't be charged)
   - Verify subscription activates in app

### Test Scenarios

**Test 1: Purchase Monthly**
- ✅ Purchase completes
- ✅ Premium features unlock
- ✅ App shows "Premium Active" status

**Test 2: Purchase Annual**
- ✅ Purchase completes
- ✅ Shows 33% savings message
- ✅ Premium features unlock

**Test 3: Restore Purchases**
- Delete and reinstall app
- Tap "Restore Purchases"
- ✅ Premium status restored

**Test 4: Subscription Upgrade**
- Purchase monthly
- Upgrade to annual
- ✅ Upgrade completes, prorates monthly

**Test 5: Subscription Expiration**
- Sandbox subscriptions renew MUCH faster:
  - 1 month subscription = 5 minutes in sandbox
  - 1 year subscription = 1 hour in sandbox
- Wait for expiration
- ✅ App reverts to free tier

---

## 🎯 Step 6: Submit for Review

### Before Submitting

- [ ] Test all subscription scenarios in sandbox
- [ ] Verify product IDs match code EXACTLY
- [ ] Add subscription screenshots to App Store listing
- [ ] Update app description to mention subscriptions
- [ ] Ensure privacy policy includes subscription info

### Submit Products

1. Go to each In-App Purchase
2. Click **Submit for Review**
3. Products must be approved before app can use them

**⚠️ First-time IAP review can take 24-48 hours**

---

## 🎯 Step 7: Update App Store Listing

### Subscription Information

Add to your **App Description:**

```
SUBSCRIPTION INFORMATION

Premium Features:
• Unlimited sermon recordings
• AI-powered transcription
• Advanced sermon summaries
• Cloud sync across devices
• Priority support
• Custom export formats

Subscription Options:
• Premium Monthly: $9.99/month
• Premium Annual: $79.99/year (Save 33%)

Free Features:
• 5 recordings per month
• 30-minute recording limit
• Basic notes
• Local storage

Payment & Renewal:
• Payment will be charged to iTunes Account at confirmation of purchase
• Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current period
• Account will be charged for renewal within 24 hours prior to the end of the current period
• Subscriptions may be managed and auto-renewal may be turned off in Account Settings after purchase
• No cancellation of the current subscription is allowed during active subscription period

Privacy Policy: https://yourwebsite.com/privacy
Terms of Service: https://yourwebsite.com/terms
```

---

## 🎯 Step 8: Handle Production Release

### When Going Live

1. **Verify all products approved:**
   - Check In-App Purchases section
   - All products should show "Ready to Submit"

2. **Submit app with IAP:**
   - Products automatically go live when app is approved
   - No separate submission needed once approved

3. **Monitor initial sales:**
   - App Store Connect → Sales and Trends
   - Watch for subscription activity

4. **Handle customer support:**
   - Refunds handled by Apple
   - Users can cancel in Settings → Apple ID → Subscriptions

---

## 📊 Revenue & Fees

### Apple's Commission

| Subscription Status | Apple's Cut | Your Cut |
|---------------------|-------------|----------|
| Year 1 | 30% | 70% |
| Year 2+ (same subscriber) | 15% | 85% |

### Example Revenue (100 subscribers)

**Monthly Subscribers (100 users × $9.99):**
- Gross Revenue: $999/month
- Year 1 Net: $699.30/month (70%)
- Year 2+ Net: $849.15/month (85%)

**Annual Subscribers (100 users × $79.99):**
- Gross Revenue: $7,999/year
- Year 1 Net: $5,599.30/year (70%)
- Year 2+ Net: $6,799.15/year (85%)

**Break-even Point:**
With API costs of ~$3-7 per user/month:
- Need ~15-20 active subscribers to break even
- Profitable at 30+ subscribers

---

## 🐛 Troubleshooting

### "Cannot connect to iTunes Store"
- **Cause:** Not using sandbox account
- **Fix:** Sign out of real Apple ID, use sandbox account

### "This In-App Purchase has already been bought"
- **Cause:** Sandbox purchase still active
- **Fix:** Wait for expiration or use different sandbox account

### Products don't load in app
- **Check 1:** Product IDs match EXACTLY (case-sensitive)
- **Check 2:** Paid Applications Agreement signed
- **Check 3:** Products submitted and approved
- **Check 4:** StoreKit configuration correct in Xcode

### "Invalid Product ID"
- **Cause:** Product ID mismatch
- **Fix:** Double-check spelling in both App Store Connect and code

### Restore Purchases doesn't work
- **Check 1:** Using same Apple ID that made purchase
- **Check 2:** Transaction.currentEntitlements correctly implemented
- **Check 3:** finish() called on all transactions

---

## 📝 Product IDs Reference

**Current Product IDs (DO NOT CHANGE):**

```swift
// Monthly Subscription
Product ID: com.tabletnotes.premium.monthly
Price: $9.99 USD
Duration: 1 Month

// Annual Subscription
Product ID: com.tabletnotes.premium.annual
Price: $79.99 USD
Duration: 1 Year
```

**If you need to change product IDs:**
1. Create new products in App Store Connect
2. Update `Subscription.swift` lines 214 & 225
3. Update `SubscriptionService.swift` lines 25-28
4. Submit new app version
5. Keep old products active for existing subscribers

---

## ✅ Launch Checklist

Before launching subscriptions:

- [ ] Paid Applications Agreement signed and approved
- [ ] Both subscription products created in App Store Connect
- [ ] Product IDs match code EXACTLY
- [ ] Products submitted for review and approved
- [ ] Tested purchases in sandbox mode
- [ ] Tested restore purchases functionality
- [ ] Tested subscription expiration
- [ ] Updated App Store description with subscription details
- [ ] Privacy policy includes subscription info
- [ ] Terms of service includes subscription terms
- [ ] Customer support email configured
- [ ] Monitoring set up for subscription metrics

---

## 🔗 Helpful Links

- App Store Connect: https://appstoreconnect.apple.com
- Sandbox Testing Guide: https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_in_xcode
- StoreKit Documentation: https://developer.apple.com/documentation/storekit
- Subscription Best Practices: https://developer.apple.com/app-store/subscriptions/

---

## 📞 Need Help?

**Common Issues:**
- Product IDs don't match → Check spelling, case-sensitivity
- Can't test → Sign Paid Applications Agreement
- Restore doesn't work → Use same Apple ID
- Products don't load → Wait 2-4 hours after creation

**Still stuck?**
- Check Apple Developer Forums
- Contact Apple Developer Support
- Review StoreKit console logs in Xcode

---

**Last Updated:** Launch Week 2025
**Bundle ID:** com.tabletnotes
**Product IDs:** com.tabletnotes.premium.{monthly|annual}
