# Creation Patterns

Full examples for the creation patterns summarized in SKILL.md.

## Functional Options — Complete Example

```go
type Server struct {
    addr         string
    readTimeout  time.Duration
    writeTimeout time.Duration
    logger       *slog.Logger
}

type Option func(*Server)

func WithAddr(addr string) Option {
    return func(s *Server) {
        s.addr = addr
    }
}

func WithReadTimeout(d time.Duration) Option {
    return func(s *Server) {
        s.readTimeout = d
    }
}

func WithLogger(l *slog.Logger) Option {
    return func(s *Server) {
        s.logger = l
    }
}

func NewServer(opts ...Option) *Server {
    s := &Server{
        addr:         ":8080",       // sensible defaults
        readTimeout:  5 * time.Second,
        writeTimeout: 10 * time.Second,
        logger:       slog.Default(),
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage:
srv := NewServer(
    WithAddr(":9090"),
    WithReadTimeout(10*time.Second),
)
```

## Functional Options vs Config Struct

```go
// Use functional options when:
// - Many optional parameters with sensible defaults
// - API evolves over time (new options don't break callers)
// - Options need validation or side effects

// Use config struct when:
// - Most fields are required
// - Configuration is loaded from file/env (easy to deserialize)
// - No need for default values
type Config struct {
    Addr     string     `yaml:"addr"`
    DBUrl    string     `yaml:"db_url"`
    LogLevel slog.Level `yaml:"log_level"`
}
```

## Constructor Pattern

Every exported type with invariants needs a constructor:

```go
// ✅ Good — constructor enforces invariants
func NewUserService(repo UserRepository, logger *slog.Logger) (*UserService, error) {
    if repo == nil {
        return nil, errors.New("user service: nil repository")
    }
    if logger == nil {
        return nil, errors.New("user service: nil logger")
    }
    return &UserService{repo: repo, logger: logger}, nil
}

// ❌ Bad — struct literal with no validation
svc := &UserService{} // nil dependencies → panic at runtime
```

Return an error from the constructor when validation is needed:

```go
// ✅ Good — constructor returns error
func NewEmailAddress(raw string) (EmailAddress, error) {
    if !isValidEmail(raw) {
        return EmailAddress{}, fmt.Errorf("invalid email: %s", raw)
    }
    return EmailAddress{value: raw}, nil
}
```

## Factory Pattern

Use when you need to create different implementations of an interface
based on runtime configuration:

```go
type Store interface {
    Get(ctx context.Context, key string) (string, error)
    Set(ctx context.Context, key, value string) error
}

func NewStore(cfg Config) (Store, error) {
    switch cfg.StoreType {
    case "redis":
        return newRedisStore(cfg.RedisAddr)
    case "memory":
        return newMemoryStore(), nil
    case "postgres":
        return newPostgresStore(cfg.DatabaseURL)
    default:
        return nil, fmt.Errorf("unknown store type: %s", cfg.StoreType)
    }
}
```

Return the interface, not a concrete type. The factory is the only place
that knows about concrete implementations.
