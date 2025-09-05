# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an NFC reader project called "影聲" (CineSpark) for iOS development. The project uses Xcode and is structured in the "Frypan NFC Reader" folder.

## Architecture

The project is structured as follows:

### Main Xcode Project Location
- **Project Folder**: `Frypan NFC Reader/`
- **Main App Files**: `Frypan NFC Reader/Frypan NFC Reader/`
- **Xcode Project File**: `Frypan NFC Reader/Frypan NFC Reader.xcodeproj/`

### Core Files
- `Frypan_NFC_ReaderApp.swift` - Main app entry point
- `ContentView.swift` - Main view (currently basic template)
- `Assets.xcassets/` - App assets and icons
- Test files for unit and UI testing

### App Details
- **App Name**: Frypan NFC Reader (temporary name)
- **Brand Name**: 影聲 (CineSpark)
- **Platform**: iOS
- **Framework**: SwiftUI
- **Language**: Swift

## Development Setup

The installation script (`1753683727739-0b3a4f6e84284f1b9afa951ab7873c29.sh`) handles:
- Node.js installation (minimum version 18, installs version 22)
- Claude Code installation
- Configuration for ZHIPU AI API integration

## Configuration

The script configures Claude Code to use:
- API base URL: https://open.bigmodel.cn/api/anthropic
- API key from ZHIPU AI platform
- Timeout: 3,000,000ms

## Notes

- This appears to be a fresh project setup for NFC reader development
- No actual NFC reader code or project structure exists yet
- The installation script is timestamped and may be a temporary setup file