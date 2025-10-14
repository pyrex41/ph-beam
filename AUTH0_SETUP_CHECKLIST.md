# Auth0 Setup Checklist

Use this checklist to verify all Auth0 configuration steps are complete.

## Pre-Setup Verification

- [ ] I have access to a web browser
- [ ] I have an email address for Auth0 registration
- [ ] I have access to GitHub account (for social login setup)
- [ ] I have access to Google account (for social login setup)

## Step 1: Auth0 Account Setup

- [ ] Visited https://auth0.com/
- [ ] Created new Auth0 account or logged into existing account
- [ ] Verified email address (if required)
- [ ] Successfully accessed Auth0 Dashboard at https://manage.auth0.com/

**Subtask 4.1 Status:** ___________

## Step 2: Create Application

- [ ] Navigated to Applications section in Auth0 Dashboard
- [ ] Clicked "Create Application" button
- [ ] Entered application name: "Collab Canvas App"
- [ ] Selected application type: "Regular Web Applications"
- [ ] Clicked "Create" button
- [ ] Application appears in Applications list

**Subtask 4.2 Status:** ___________

## Step 3: Configure Callback URLs

- [ ] Opened "Collab Canvas App" settings
- [ ] Found "Application URIs" section
- [ ] Added to "Allowed Callback URLs": `http://localhost:4000/auth/callback`
- [ ] Added to "Allowed Logout URLs": `http://localhost:4000`
- [ ] Added to "Allowed Web Origins": `http://localhost:4000`
- [ ] Clicked "Save Changes"
- [ ] Verified no error messages appeared

**Subtask 4.3 Status:** ___________

## Step 4: Enable Google Social Login

- [ ] Navigated to Authentication > Social in sidebar
- [ ] Located Google connection in list
- [ ] Clicked on Google connection
- [ ] Toggled "Enable" switch to ON
- [ ] Chose configuration method:
  - [ ] Option A: Using Auth0 Dev Keys (quickest)
  - [ ] Option B: Using own Google OAuth credentials (recommended)
    - [ ] Created OAuth 2.0 Client ID in Google Cloud Console
    - [ ] Added authorized redirect URI with Auth0 domain
    - [ ] Copied Client ID and Client Secret to Auth0
- [ ] Clicked "Applications" tab in Google connection settings
- [ ] Verified "Collab Canvas App" is enabled/checked
- [ ] Clicked "Save Changes"

**Subtask 4.4a (Google) Status:** ___________

## Step 5: Enable GitHub Social Login

- [ ] Navigated to Authentication > Social in sidebar
- [ ] Located GitHub connection in list
- [ ] Clicked on GitHub connection
- [ ] Visited https://github.com/settings/developers
- [ ] Clicked "New OAuth App"
- [ ] Filled in OAuth App details:
  - [ ] Application name: "Collab Canvas"
  - [ ] Homepage URL: `http://localhost:4000`
  - [ ] Authorization callback URL: `https://[YOUR_AUTH0_DOMAIN]/login/callback`
- [ ] Clicked "Register application"
- [ ] Copied GitHub Client ID
- [ ] Generated and copied GitHub Client Secret
- [ ] Pasted GitHub Client ID into Auth0
- [ ] Pasted GitHub Client Secret into Auth0
- [ ] Clicked "Applications" tab in GitHub connection settings
- [ ] Verified "Collab Canvas App" is enabled/checked
- [ ] Clicked "Save Changes"

**Subtask 4.4b (GitHub) Status:** ___________

## Step 6: Copy Credentials

- [ ] Navigated to Applications > Collab Canvas App
- [ ] Clicked "Settings" tab
- [ ] Located and copied **Domain** (e.g., dev-abc123.us.auth0.com)
- [ ] Located and copied **Client ID**
- [ ] Clicked "Show" and copied **Client Secret**
- [ ] Executed command: `cp .env.example .env`
- [ ] Opened `.env` file in editor
- [ ] Pasted Domain into `AUTH0_DOMAIN`
- [ ] Pasted Client ID into `AUTH0_CLIENT_ID`
- [ ] Pasted Client Secret into `AUTH0_CLIENT_SECRET`
- [ ] Verified `AUTH0_CALLBACK_URL` is set to `http://localhost:4000/auth/callback`
- [ ] Saved `.env` file
- [ ] Verified `.env` is NOT tracked in git (run `git status`)

**Subtask 4.5 Status:** ___________

## Final Verification Checklist

- [ ] Auth0 application "Collab Canvas App" exists in dashboard
- [ ] Application type is "Regular Web Application"
- [ ] Callback URL includes `http://localhost:4000/auth/callback`
- [ ] Logout URL includes `http://localhost:4000`
- [ ] Web Origins includes `http://localhost:4000`
- [ ] Google social connection is enabled and linked to application
- [ ] GitHub social connection is enabled and linked to application
- [ ] All three credentials are copied to `.env` file:
  - AUTH0_DOMAIN
  - AUTH0_CLIENT_ID
  - AUTH0_CLIENT_SECRET
- [ ] `.env` file is NOT in git tracking (verify with `git status`)
- [ ] `.gitignore` includes `.env` entry

## Security Verification

- [ ] `.env` file contains actual credential values (not placeholders)
- [ ] `.env` file is listed in `.gitignore`
- [ ] Running `git status` does NOT show `.env` as a tracked file
- [ ] Credentials are stored securely and not shared publicly
- [ ] Client Secret was not copied to clipboard history for too long

## Documentation Reference

For detailed instructions, see:
- `AUTH0_SETUP_GUIDE.md` - Complete step-by-step setup guide
- `.env.example` - Environment variable template

## Task Completion

Once all checkboxes are marked:

```bash
# Mark Task 4 as complete
task-master set-status --id=4 --status=done
```

## Next Steps

After completing this task:
1. Proceed to Task 5: "Implement Auth0 Authentication Routes"
2. The credentials in `.env` will be used by the backend
3. Test authentication once routes are implemented

---

**Setup Completed:** __________ (Date)
**Verified By:** __________ (Your Name)
