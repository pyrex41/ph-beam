# Auth0 Setup Guide for Collab Canvas

This guide walks you through setting up Auth0 authentication for the Collab Canvas application.

## Prerequisites

- A web browser
- Email address for Auth0 account
- GitHub and Google accounts (for social login configuration)

## Step-by-Step Setup Instructions

### Step 1: Create Auth0 Account

1. Visit [https://auth0.com/](https://auth0.com/)
2. Click "Sign Up" in the top-right corner
3. Choose one of the following signup methods:
   - Sign up with Google
   - Sign up with GitHub
   - Sign up with email
4. Complete the signup process
5. Verify your email if required
6. You'll be redirected to the Auth0 Dashboard at [https://manage.auth0.com/](https://manage.auth0.com/)

**Note:** The free tier is sufficient for development and includes:
- 7,000 active users
- Unlimited logins
- Social login providers

### Step 2: Create a Regular Web Application

1. In the Auth0 Dashboard, navigate to **Applications** in the left sidebar
2. Click the **"Create Application"** button
3. In the dialog that appears:
   - **Name:** Enter "Collab Canvas App" (or your preferred name)
   - **Type:** Select **"Regular Web Applications"**
   - Click **"Create"**
4. You'll be taken to the Quick Start page for your new application

### Step 3: Configure Application Settings

1. Click on the **"Settings"** tab at the top of the application page
2. Scroll down to the **Application URIs** section
3. Configure the following fields:

   **Allowed Callback URLs:**
   ```
   http://localhost:4000/auth/callback
   ```
   (Add production URLs later when deploying)

   **Allowed Logout URLs:**
   ```
   http://localhost:4000
   ```

   **Allowed Web Origins:**
   ```
   http://localhost:4000
   ```

4. Scroll to the bottom and click **"Save Changes"**

### Step 4: Enable Google Social Login

1. Navigate to **Authentication > Social** in the left sidebar
2. Find **Google** in the list of social connections
3. Click on **Google** to configure it
4. Toggle the switch to **Enable** the connection
5. You have two options:

   **Option A: Use Auth0 Dev Keys (Quickest for Development)**
   - Simply enable the connection
   - Auth0 provides default development credentials
   - Note: These have limitations and should be replaced for production

   **Option B: Use Your Own Google OAuth Credentials (Recommended)**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select an existing one
   - Enable the Google+ API
   - Go to **Credentials** and create **OAuth 2.0 Client ID**
   - Set the application type to **Web application**
   - Add authorized redirect URI: `https://YOUR_AUTH0_DOMAIN/login/callback`
   - Copy the **Client ID** and **Client Secret**
   - Paste them into the Auth0 Google connection settings

6. Click on the **"Applications"** tab within the Google connection settings
7. Ensure your "Collab Canvas App" is checked/enabled
8. Click **"Save Changes"**

### Step 5: Enable GitHub Social Login

1. Navigate to **Authentication > Social** in the left sidebar
2. Find **GitHub** in the list of social connections
3. Click on **GitHub** to configure it
4. You need to create GitHub OAuth credentials:

   **Create GitHub OAuth App:**
   - Go to [GitHub Developer Settings](https://github.com/settings/developers)
   - Click **"New OAuth App"**
   - Fill in the details:
     - **Application name:** Collab Canvas
     - **Homepage URL:** `http://localhost:4000`
     - **Authorization callback URL:** `https://YOUR_AUTH0_DOMAIN/login/callback`
       (Replace YOUR_AUTH0_DOMAIN with your actual Auth0 domain from Step 6)
   - Click **"Register application"**
   - Copy the **Client ID**
   - Click **"Generate a new client secret"** and copy the secret

5. Back in Auth0, paste the GitHub **Client ID** and **Client Secret**
6. Click on the **"Applications"** tab within the GitHub connection settings
7. Ensure your "Collab Canvas App" is checked/enabled
8. Click **"Save Changes"**

### Step 6: Copy Auth0 Credentials

1. Go back to **Applications > Applications** in the left sidebar
2. Click on your **"Collab Canvas App"**
3. Go to the **"Settings"** tab
4. Locate the following credentials (near the top of the page):
   - **Domain** (e.g., `dev-abc123.us.auth0.com`)
   - **Client ID** (a long alphanumeric string)
   - **Client Secret** (click "Show" to reveal, then copy)

5. Create a `.env` file in the project root (copy from `.env.example`):
   ```bash
   cp .env.example .env
   ```

6. Open `.env` and fill in the Auth0 credentials:
   ```env
   AUTH0_DOMAIN="dev-abc123.us.auth0.com"
   AUTH0_CLIENT_ID="your_actual_client_id_here"
   AUTH0_CLIENT_SECRET="your_actual_client_secret_here"
   AUTH0_CALLBACK_URL="http://localhost:4000/auth/callback"
   ```

**IMPORTANT SECURITY NOTES:**
- Never commit the `.env` file to version control
- The `.gitignore` file should already exclude `.env`
- Keep your Client Secret confidential
- Rotate credentials if they are ever exposed

### Step 7: Verify Configuration

Before marking this task complete, verify the following in your Auth0 Dashboard:

- [ ] Application is created and named "Collab Canvas App"
- [ ] Application type is "Regular Web Application"
- [ ] Callback URL `http://localhost:4000/auth/callback` is added
- [ ] Logout URL `http://localhost:4000` is added
- [ ] Google social connection is enabled and linked to your application
- [ ] GitHub social connection is enabled and linked to your application
- [ ] All credentials are copied to `.env` file
- [ ] `.env` file is not tracked in git (verify with `git status`)

## Testing Your Configuration

Once the backend authentication routes are implemented (Task 5), you can test the Auth0 integration:

1. Start your application
2. Navigate to the login page
3. You should see options to:
   - Sign in with Google
   - Sign in with GitHub
   - Sign in with email/password (if database connection enabled)
4. Test each social login to ensure it redirects properly

## Troubleshooting

### Common Issues

**Issue: Callback URL mismatch error**
- Solution: Double-check that the callback URL in Auth0 exactly matches the one your application uses

**Issue: Social login not appearing**
- Solution: Ensure the social connection is enabled AND linked to your application in the Applications tab

**Issue: "Access Denied" error**
- Solution: Check that the social provider (Google/GitHub) OAuth app is configured correctly with the right callback URL

**Issue: Application not found**
- Solution: Verify that you're using the correct Domain, Client ID, and Client Secret from the correct application

## Next Steps

After completing this setup:
1. Mark Task 4 as complete in Task Master
2. Proceed to Task 5: "Implement Auth0 Authentication Routes"
3. The credentials you've configured will be used in the backend implementation

## Additional Resources

- [Auth0 Documentation](https://auth0.com/docs)
- [Auth0 Node.js SDK](https://github.com/auth0/node-auth0)
- [Google OAuth 2.0 Setup](https://developers.google.com/identity/protocols/oauth2)
- [GitHub OAuth Apps](https://docs.github.com/en/developers/apps/building-oauth-apps)

## Support

If you encounter issues:
1. Check the [Auth0 Community](https://community.auth0.com/)
2. Review the [Auth0 Documentation](https://auth0.com/docs)
3. Contact Auth0 support through the dashboard

---

**Configuration Complete!** Once you've verified all steps, you're ready to integrate Auth0 into your application code.
