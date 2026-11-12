/// These operations serialize inside their sync service and never load/seek a
/// book. Keep them independent of the player command queue during slow I/O.
const independentSyncCommands = {
  'sync-status',
  'sync-enable',
  'sync-now',
  'folder-sync-status',
  'folder-sync-configure',
  'folder-sync-now',
};

/// Long-running diagnostics that never touch playback or the library. They
/// use their own endpoint so a slow NAS check cannot block player commands.
const diagnosticCommands = {'smb-check'};
