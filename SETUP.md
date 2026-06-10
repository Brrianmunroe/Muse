# Muse — Setup Guide

## Step 1: Create the Xcode Project

1. Open Xcode
2. File → New → Project
3. Choose **App** (under iOS)
4. Settings:
   - Product Name: **Muse**
   - Team: Your Apple Developer account
   - Organization Identifier: Something like `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
5. Save it inside the `Muse` folder on your Desktop
6. **Delete** the default ContentView.swift that Xcode creates (we have our own files)

## Step 2: Add the Source Files

The source files are already in the `Muse/` subfolder. In Xcode:
1. Right-click the Muse group in the file navigator
2. "Add Files to Muse..."
3. Select all the folders: App, Models, Views, ViewModels, Services, Extensions
4. Make sure "Copy items if needed" is **unchecked** (files are already in the right place)
5. Make sure "Create groups" is selected

## Step 3: Add the Supabase Package

1. In Xcode: File → Add Package Dependencies...
2. Paste this URL: `https://github.com/supabase/supabase-swift.git`
3. Set version rule to "Up to Next Major" from `2.0.0`
4. Click Add Package
5. Check the **Supabase** library, click Add Package

## Step 4: Set Up Supabase

1. Go to [supabase.com](https://supabase.com) and create a free account
2. Create a new project (remember the database password!)
3. Once the project is ready, go to **Settings → API**
4. Copy your **Project URL** and **anon/public key**

### Add the keys to your app:

In Xcode, open `Info.plist` (or the Info tab of your target) and add two rows:
- Key: `SUPABASE_URL` → Value: your project URL
- Key: `SUPABASE_ANON_KEY` → Value: your anon key

### Run the database migration:

1. In your Supabase dashboard, go to **SQL Editor**
2. Click **New Query**
3. Paste the entire contents of `Supabase/migrations/001_initial_schema.sql`
4. Click **Run**

This creates all the tables, security policies, and the image storage bucket.

## Step 5: Enable Apple Sign-In (Optional)

If you want Apple Sign-In:
1. In Xcode: Select your target → Signing & Capabilities → + Capability → **Sign in with Apple**
2. In Supabase dashboard: Authentication → Providers → Apple → Enable and configure

## Step 6: Run!

1. Select an iPhone simulator from the device dropdown
2. Press Cmd+R to build and run
3. You should see the Muse sign-in screen
