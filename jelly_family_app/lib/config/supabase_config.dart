class SupabaseConfig {
  /// You can override these at build/run time:
  /// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gbzkrbepxejjcffyohcb.supabase.co',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiemtyYmVweGVqamNmZnlvaGNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2ODkzMjQsImV4cCI6MjA4NTI2NTMyNH0.UVfArhZQB4cUw-em0IvYbgCKbSPFXA5jnMjI0emNldE',
  );
}

