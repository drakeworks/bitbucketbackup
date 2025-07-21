# Bitbucket Repository Backup Script

Bash script to automatically backup all repositories and branches from a Bitbucket workspace, updated to support Atlassian's API Tokens.

## ✨ Features

- 🔄 **Automatic repository discovery** - Fetches all repositories from your Bitbucket workspace
- 🌿 **All branches backup** - Backs up every branch in each repository
- 🔐 **Secure authentication** - Uses Atlassian API tokens for authentication
- 📊 **Progress tracking** - Real-time progress bar and detailed logging
- 🛡️ **Error recovery** - Automatic retry with exponential backoff
- ⚡ **Parallel processing** - Configurable parallel job execution
- 🔍 **Backup verification** - Verify backups after completion
- 🎯 **Dry-run mode** - Preview what would be backed up
- 📝 **Comprehensive logging** - Colored, timestamped log messages
- 📈 **Summary reports** - Detailed backup statistics and results

## 🚀 Quick Start

1. **Clone this repository:**
   ```bash
   git clone <your-repo-url>
   cd bitbucketbackup
   ```

2. **Create your configuration file:**
   ```bash
   cp config.env.example config.env
   ```

3. **Edit `config.env` with your Bitbucket credentials:**
   ```bash
   # Bitbucket Configuration
   ATLASSIAN_EMAIL="your-email@example.com"
   API_TOKEN="your-api-token-here"
   ORGNAME="your-workspace-name"
   BACKUP_DIR="/path/to/your/backup/directory"
   ```

4. **Run the backup:**
   ```bash
   chmod +x main.sh
   ./main.sh
   ```

## 📋 Getting Your Bitbucket API Token

1. Go to [Atlassian Account Settings > Security > API tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click "Create API token with scopes"
3. Give the API token a name and set an expiry date, then click "Next"
4. Select "Bitbucket" as the app and click "Next"
5. Select the following scopes (permissions):
   - **Repositories: Read**
   - **Workspace membership: Read**
6. Click "Next" to review your token
7. Click "Create token"
8. Copy the generated API token and paste it in your `config.env` file

**Note:** API tokens are created through your Atlassian account settings, not through Bitbucket directly. They provide better security and are the recommended authentication method for Bitbucket APIs.

## 🎛️ Command Line Options

```bash
Usage: main.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -c, --config FILE       Specify configuration file (default: config.env)
    -d, --dry-run          Show what would be done without executing
    -v, --verbose          Enable verbose output
    -s, --skip-existing    Skip repositories that already exist
    -j, --jobs N           Number of parallel jobs (default: 4)
    --verify               Verify backups after completion

EXAMPLES:
    ./main.sh                    # Run with default settings
    ./main.sh --dry-run          # See what would be backed up
    ./main.sh --verbose --jobs 8 # Verbose output with 8 parallel jobs
    ./main.sh --config my.env    # Use custom config file
    ./main.sh --verify           # Verify backups after completion
```

## 🔧 Advanced Usage

### Dry Run Mode
Preview what the script would do without making any changes:
```bash
./main.sh --dry-run
```

### Verbose Output
Get detailed information about each step:
```bash
./main.sh --verbose
```

### Parallel Processing
Speed up backups by running multiple repositories in parallel:
```bash
./main.sh --jobs 8  # Use 8 parallel jobs
```

### Skip Existing Repositories
Only backup new repositories, skip existing ones:
```bash
./main.sh --skip-existing
```

### Backup Verification
Verify that all backups are valid after completion:
```bash
./main.sh --verify
```

### Custom Configuration
Use a different configuration file:
```bash
./main.sh --config production.env
```

## 📊 What Gets Backed Up

- ✅ All repositories in your specified workspace
- ✅ All branches in each repository (main, master, develop, feature branches, etc.)
- ✅ Complete Git history and commits
- ✅ All tags and refs
- ✅ Repository metadata and structure

## 🛡️ Security Notes

- The `config.env` file is excluded from Git via `.gitignore`
- Never commit your actual API token to version control
- The example file (`config.env.example`) is safe to commit as it contains no real credentials
- All sensitive data is validated and sanitized before use

## 📈 Performance Features

- **Parallel Processing**: Configurable number of concurrent repository backups
- **Retry Logic**: Automatic retry with exponential backoff for network operations
- **Progress Tracking**: Real-time progress bar and detailed statistics
- **Error Recovery**: Graceful handling of failures with detailed reporting
- **Memory Efficient**: Processes repositories one at a time to minimize memory usage

## 🔍 Error Handling

The script includes comprehensive error handling:

- **Network Failures**: Automatic retry with exponential backoff
- **Authentication Errors**: Clear error messages for invalid credentials
- **Permission Issues**: Validation of backup directory permissions
- **Repository Access**: Handling of private repositories and access restrictions
- **Disk Space**: Validation of available disk space before backup

## 📋 Requirements

- **Bash shell** (version 4.0 or higher)
- **Git** (version 2.0 or higher)
- **curl** (for API communication)
- **jq** (optional, for better JSON parsing)

## 📝 Logging

The script provides comprehensive logging with different levels:

- **ERROR**: Critical errors that prevent operation
- **WARN**: Non-critical issues that don't stop execution
- **INFO**: General information about progress
- **SUCCESS**: Successful operations

All logs include timestamps and are color-coded for easy reading.

## 📊 Output Example

```
[2024-07-21 10:30:15] [INFO] Found 38 repositories to backup
[2024-07-21 10:30:16] [INFO] Created backup directory: /Users/macbook/Downloads/Backup
[##################################################] 100% (38/38)
[2024-07-21 10:35:22] [SUCCESS] Completed backup of my-repo (5/5 branches updated)

==========================================
           BACKUP SUMMARY
==========================================
Total repositories: 38
Successful backups: 38
Failed backups: 0
Backup location: /Users/macbook/Downloads/Backup
Backup size: 2.1G
Backup time: Sun Jul 21 10:35:22 2024
==========================================
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT License

Copyright (c) 2024 Bitbucket Backup Script

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
