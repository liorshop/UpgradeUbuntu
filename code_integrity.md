# Code Integrity Guidelines for AI Development

## Initial Session Setup

### Repository State Assessment
```bash
# Before starting any development:
1. Get complete repository state
2. Map all existing functions
3. Document file dependencies
4. Identify critical components
5. Create function dependency graph
```

### Critical Components Tracking
```plaintext
For each project, maintain:

CRITICAL_FUNCTIONS:
□ List all core functions with descriptions
□ Mark functions that cannot be modified
□ Document function dependencies
□ Note required return values/states

REQUIRED_FILES:
□ List all essential files
□ Document file purposes
□ Note file dependencies
□ Track file permissions

DEPENDENCIES:
□ File-to-file dependencies
□ Function-to-function calls
□ Environmental requirements
□ External service dependencies
```

## Development Protocol

### Before Code Modification
```plaintext
PRE_CHANGE_CHECKLIST:
□ Get current file content
□ List targeted functions
□ Document planned changes
□ Verify dependencies
□ Check for side effects

VERIFICATION_STEPS:
□ Validate current functionality
□ Document critical paths
□ Check error handlers
□ Review logging mechanisms
□ Verify state management
```

### During Code Updates
```plaintext
UPDATE_PROTOCOL:
1. NO partial file updates
2. Keep complete function blocks
3. Maintain error handling
4. Preserve logging
5. Document all changes

INTEGRITY_CHECKS:
- Track all modified functions
- Verify critical functions exist
- Maintain dependency chain
- Check state transitions
- Validate error paths
```

### Post-Update Verification
```plaintext
POST_UPDATE_CHECKLIST:
□ All critical functions present
□ Error handling intact
□ Logging maintained
□ Dependencies satisfied
□ States preserved
```

## AI Assistant Constraints

### Required Prompt Structure
```plaintext
PROMPT_REQUIREMENTS:

START_CRITICAL_FUNCTIONS:
- [list of must-preserve functions]

REQUIRED_FILES:
- [list of essential files]

DEPENDENCIES:
- [list of dependencies]

NO_PARTIAL_UPDATES: true/false

MODIFICATION_SCOPE:
- [specific changes requested]

VERIFICATION_REQUIRED: true/false
```

### Operation Protocol
```plaintext
For each code modification:

1. GET current state
2. DOCUMENT existing functionality
3. VERIFY critical components
4. IMPLEMENT changes
5. VALIDATE integrity
6. REPORT modifications
```

### Response Requirements
```plaintext
Each response must include:

1. List of files modified
2. Functions changed/added/removed
3. Dependency impacts
4. Verification steps taken
5. Integrity confirmation
```

## Error Prevention

### Common Pitfalls
```plaintext
1. Function Loss Prevention:
   - Always get full file content
   - No partial updates
   - Verify after changes

2. Dependency Breaking:
   - Map all dependencies
   - Check call chains
   - Verify interfaces

3. State Corruption:
   - Track state changes
   - Verify transitions
   - Maintain atomicity
```

### Quality Assurance
```plaintext
VERIFICATION_STEPS:
1. Function presence
2. Error handling
3. Logging integrity
4. State management
5. Dependency chain
6. Security measures
```

## Documentation Requirements

### Change Documentation
```plaintext
For each update:
1. List modified files
2. Document function changes
3. Note dependency updates
4. Mark affected states
5. Record verification steps
```

### Version Control
```plaintext
COMMIT_TEMPLATE:
[Component] Action Description

- Files modified:
  - file1.sh: [changes]
  - file2.sh: [changes]

- Functions affected:
  - function1(): [changes]
  - function2(): [changes]

- Verification steps:
  [list steps taken]

- Dependencies checked:
  [list verifications]
```

## Emergency Procedures

### Recovery Steps
```plaintext
1. Code Integrity Loss:
   - Revert to last known good state
   - Verify critical functions
   - Check dependencies
   - Validate state management

2. Function Loss:
   - Check version control
   - Restore missing functions
   - Verify dependencies
   - Test functionality
```