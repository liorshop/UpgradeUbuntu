# Ubuntu Upgrade Script Development Guidelines

## Critical Components

### Required Files
- `upgrade_manager.sh` - Main script
- `pre_upgrade_cleanup.sh` - Pre-upgrade cleanup
- `post_upgrade_setup.sh` - Post-upgrade setup
- `common.sh` - Shared functions
- `logger.sh` - Logging system
- `state_manager.sh` - State management

### Critical Functions
These functions must be preserved across all updates:

#### State Management
- `get_state()` - Get current upgrade state
- `save_state()` - Save new state
- `acquire_lock()` - Process lock management
- `release_lock()` - Lock cleanup

#### Core Upgrade Functions
- `setup_next_boot()` - Configure next boot
- `perform_upgrade()` - Core upgrade process
- `validate_system()` - System validation

#### Database Management
- `backup_postgres()` - Database backup
- `setup_postgres()` - Database restoration

### Dependencies Between Files
```plaintext
common.sh
├── logger.sh
├── state_manager.sh
└── upgrade_manager.sh
    ├── pre_upgrade_cleanup.sh
    └── post_upgrade_setup.sh
```

## Development Guidelines

### Before Making Changes
1. Verify current state of all files
2. Document existing functions
3. Check dependencies
4. Create backup if needed

### During Updates
1. Never update files partially
2. Verify all critical functions remain intact
3. Check function dependencies
4. Maintain error handling
5. Preserve logging

### After Changes
1. Verify all critical functions exist
2. Check file permissions
3. Test state transitions
4. Validate error handling

## Code Quality Standards

### Error Handling
```bash
# Required in all scripts
trap 'handle_error ${LINENO}' ERR

# All critical commands should have error handling
command || {
    log "ERROR" "${COMPONENT}" "Failed to execute command"
    return 1
}
```

### Logging
```bash
# All significant actions must be logged
log "INFO" "${COMPONENT}" "Starting action"

# All errors must be logged
log "ERROR" "${COMPONENT}" "Action failed"
```

### State Management
```bash
# State changes must be atomic
save_state() {
    echo "$1" > "${STATE_FILE}.tmp" && \
    mv "${STATE_FILE}.tmp" "${STATE_FILE}"
}
```

## Testing Requirements

### Pre-Deployment Checks
1. Database backup functionality
2. Service management
3. State transitions
4. Error recovery
5. Reboot handling

### Mandatory Test Cases
1. Clean state progression
2. Error handling
3. Service management
4. Database operations
5. Network interruptions

## Common Pitfalls

1. Function Loss
   - Always verify complete file content
   - Check critical functions after updates

2. Dependency Breaking
   - Maintain source order in files
   - Check dependent function calls

3. Error Handling Gaps
   - Every critical operation needs error handling
   - Maintain trap handlers

4. State Corruption
   - Use atomic operations
   - Verify state transitions

## Version Control Guidelines

### Commit Messages
```plaintext
Format:
[Component] Brief description

- Detailed change 1
- Detailed change 2
- Files modified
- Functions changed
```

### Branch Management
- Main branch should always be stable
- Test changes in development branch
- Verify all critical functions before merge

## Emergency Procedures

### Recovery Steps
1. Check state file
2. Verify service status
3. Check logs
4. Restore from known good state

### Debug Information
```bash
# State verification
cat ${STATE_FILE}

# Service status
systemctl status ubuntu-upgrade

# Log examination
tail -f ${LOG_FILE}
```
