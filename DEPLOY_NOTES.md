# MediaNest — what changed and how to deploy

## 1. Deploy the backend (required — the app fixes depend on it)

```bash
cd functions
npm install
firebase deploy --only functions
```

`busboy` was added to `package.json` (it replaces `multer`, which was never
listed as a dependency and cannot read uploads on Cloud Functions anyway).

The function now runs with 1 GiB memory and a 300 s timeout so video
transcription has room to finish.

## 2. Publish the security rules

`firestore.rules` and `storage.rules` are in this folder (next to
`functions/`). If your `firebase.json` does not reference them yet, add:

```json
{
  "firestore": { "rules": "firestore.rules" },
  "storage":   { "rules": "storage.rules" }
}
```

then:

```bash
firebase deploy --only firestore:rules,storage
```

The Storage rules read Firestore to check the subscription. The first time
you deploy them Firebase asks to grant that permission — say yes. (If you
paste them in the Firebase console instead, the console shows the same
prompt.)

## 3. Owner accounts (always Pro)

- princenwanozie6666@gmail.com
- ifeanyinwanozie6666@gmail.com

Sign in to the app with **Google** using one of these accounts. They are
treated as Pro everywhere (app, backend, security rules) in every build,
including the Play Store release, with a $25/month AI testing allowance.

The list lives in three places — keep them identical if you ever change it:

- `functions/lib/middleware.js` → `OWNER_EMAILS`
- `lib/providers/premium_provider.dart` → `ownerEmails`
- `firestore.rules` and `storage.rules` → `isOwnerAccount()`

The email must be verified (Google sign-in always is). An unverified
email/password account using one of these addresses does NOT get Pro.

## 4. New / changed API endpoints

| Endpoint | Change |
|---|---|
| `POST /analyzeVideo` | Upload parsing rewritten (busboy + rawBody). Returns `segments`, `language`, `hasSpeech`. |
| `POST /processRepurposeVariants` | Uses the real transcript. `subtitle` returns real timed subtitles. `translate` accepts `targetLanguage`. Returns `usedTranscript`. |
| `GET /getDailyChallenge` | Pro only. Uses niche + goal + experience. Returns `steps`, `tip`, `points`. |
| `POST /completeDailyChallenge` | No composite index needed. Streak resets after a missed day. Returns `points`, `pointsEarned`. |
| `GET /getCoachIdeas` | NEW — AI ideas + tips + 30-day activity (cached per day, `?refresh=1`). |
| `GET /getCoachPlan` | NEW — AI learning path for the user's goal/level. |
| `POST /setCoachStepDone` | NEW — saves learning-path progress. |
| `GET /verifyPremium` | Also returns `isOwner`. |
| `GET /getLibraryStats` | Also returns the `stats` shape older builds read. |

No Firestore composite indexes are required.
