#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="swoole"

echo "======================================"
echo " Creating Swoole mini-framework"
echo "======================================"

# --------------------------------------------------
# Check dependencies
# --------------------------------------------------

command -v php >/dev/null 2>&1 || {
    echo "ERROR: PHP is not installed."
    exit 1
}

command -v composer >/dev/null 2>&1 || {
    echo "ERROR: Composer is not installed."
    exit 1
}

if ! php -m | grep -qi "^swoole$"; then
    echo "ERROR: PHP Swoole extension is not installed."
    echo
    echo "Check with:"
    echo "  php -m | grep -i swoole"
    echo
    exit 1
fi

echo "PHP:      $(php -v | head -n 1)"
echo "Swoole:   $(php --ri swoole | grep '^Version' | head -n 1 || true)"
echo "Composer: $(composer --version | head -n 1)"
echo

# --------------------------------------------------
# Create directories
# --------------------------------------------------

echo "==> Creating directories"

mkdir -p "$PROJECT_DIR"/{
app/Controllers,
app/Exceptions,
app/Middleware,
app/Services,
commands,
config,
contracts,
providers,
src/Middleware,
src/Exceptions,
src/Console,
start,
tests/functional
}

cd "$PROJECT_DIR"

# --------------------------------------------------
# composer.json
# --------------------------------------------------

echo "==> Creating composer.json"

cat > composer.json <<'EOF'
{
  "name": "benchmark/swoole",
  "description": "Minimal AdonisJS-inspired framework running on Swoole",
  "type": "project",
  "require": {
    "php": "^8.2"
  },
  "autoload": {
    "psr-4": {
      "App\\": "app/",
      "Framework\\": "src/"
    }
  },
  "scripts": {
    "server": "php server.php"
  }
}
EOF

# --------------------------------------------------
# Application
# --------------------------------------------------

echo "==> Creating Application.php"

cat > src/Application.php <<'EOF'
<?php

namespace Framework;

use Throwable;

class Application
{
    private Container $container;

    public function __construct(
        private readonly string $basePath
    ) {
        $this->container = new Container();
    }

    public function boot(): void
    {
        require $this->basePath('start/kernel.php');
    }

    public function handle($request, $response): void
    {
        try {
            $router = $this->container->make(Router::class);

            $router->dispatch($request, $response);
        } catch (Throwable $exception) {
            $handler = $this->container->make(
                Exceptions\ExceptionHandler::class
            );

            $handler->handle($exception, $response);
        }
    }

    public function container(): Container
    {
        return $this->container;
    }

    public function basePath(string $path = ''): string
    {
        if ($path === '') {
            return $this->basePath;
        }

        return $this->basePath . '/' . ltrim($path, '/');
    }
}
EOF

# --------------------------------------------------
# Container
# --------------------------------------------------

echo "==> Creating Container.php"

cat > src/Container.php <<'EOF'
<?php

namespace Framework;

use RuntimeException;

class Container
{
    private array $bindings = [];

    public function singleton(
        string $abstract,
        callable $factory
    ): void {
        $this->bindings[$abstract] = [
            'factory' => $factory,
            'instance' => null,
        ];
    }

    public function make(string $abstract): mixed
    {
        if (!isset($this->bindings[$abstract])) {
            throw new RuntimeException(
                "Nothing is bound for [$abstract]"
            );
        }

        $binding = &$this->bindings[$abstract];

        if ($binding['instance'] === null) {
            $binding['instance'] =
                ($binding['factory'])($this);
        }

        return $binding['instance'];
    }
}
EOF

# --------------------------------------------------
# Request
# --------------------------------------------------

echo "==> Creating Request.php"

cat > src/Request.php <<'EOF'
<?php

namespace Framework;

class Request
{
    public function __construct(
        private readonly object $swooleRequest
    ) {
    }

    public function method(): string
    {
        return $this->swooleRequest->server['request_method'] ?? 'GET';
    }

    public function path(): string
    {
        return $this->swooleRequest->server['request_uri'] ?? '/';
    }

    public function header(string $name): ?string
    {
        $headers = $this->swooleRequest->header ?? [];

        return $headers[strtolower($name)] ?? null;
    }

    public function query(string $key, mixed $default = null): mixed
    {
        return $this->swooleRequest->get[$key] ?? $default;
    }

    public function all(): array
    {
        return $this->swooleRequest->get ?? [];
    }

    public function raw(): object
    {
        return $this->swooleRequest;
    }
}
EOF

# --------------------------------------------------
# Response
# --------------------------------------------------

echo "==> Creating Response.php"

cat > src/Response.php <<'EOF'
<?php

namespace Framework;

class Response
{
    public function __construct(
        private readonly object $swooleResponse
    ) {
    }

    public function json(
        array $data,
        int $status = 200
    ): void {
        $this->swooleResponse->status($status);

        $this->swooleResponse->header(
            'Content-Type',
            'application/json'
        );

        $this->swooleResponse->end(
            json_encode(
                $data,
                JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
            )
        );
    }

    public function text(
        string $content,
        int $status = 200
    ): void {
        $this->swooleResponse->status($status);

        $this->swooleResponse->header(
            'Content-Type',
            'text/plain; charset=utf-8'
        );

        $this->swooleResponse->end($content);
    }

    public function status(int $status): self
    {
        $this->swooleResponse->status($status);

        return $this;
    }

    public function raw(): object
    {
        return $this->swooleResponse;
    }
}
EOF

# --------------------------------------------------
# Router
# --------------------------------------------------

echo "==> Creating Router.php"

cat > src/Router.php <<'EOF'
<?php

namespace Framework;

use RuntimeException;

class Router
{
    private array $routes = [];

    public function get(
        string $path,
        array $handler
    ): void {
        $this->add('GET', $path, $handler);
    }

    public function post(
        string $path,
        array $handler
    ): void {
        $this->add('POST', $path, $handler);
    }

    public function put(
        string $path,
        array $handler
    ): void {
        $this->add('PUT', $path, $handler);
    }

    public function delete(
        string $path,
        array $handler
    ): void {
        $this->add('DELETE', $path, $handler);
    }

    private function add(
        string $method,
        string $path,
        array $handler
    ): void {
        $this->routes[$method][$path] = $handler;
    }

    public function dispatch(
        $swooleRequest,
        $swooleResponse
    ): void {
        $request = new Request($swooleRequest);
        $response = new Response($swooleResponse);

        $method = $request->method();
        $path = $request->path();

        $handler = $this->routes[$method][$path] ?? null;

        if ($handler === null) {
            $response->json([
                'error' => 'Not Found',
                'status' => 404,
            ], 404);

            return;
        }

        [$controllerClass, $action] = $handler;

        $controller = new $controllerClass();

        if (!method_exists($controller, $action)) {
            throw new RuntimeException(
                "Action [$action] not found on [$controllerClass]"
            );
        }

        $result = $controller->$action($request);

        if ($result instanceof Response) {
            return;
        }

        if (is_array($result)) {
            $response->json($result);

            return;
        }

        $response->text((string) $result);
    }
}
EOF

# --------------------------------------------------
# Exception Handler
# --------------------------------------------------

echo "==> Creating ExceptionHandler.php"

cat > src/Exceptions/ExceptionHandler.php <<'EOF'
<?php

namespace Framework\Exceptions;

use Throwable;

class ExceptionHandler
{
    public function handle(
        Throwable $exception,
        $response
    ): void {
        $response->status(500);

        $response->header(
            'Content-Type',
            'application/json'
        );

        $response->end(
            json_encode([
                'error' => 'Internal Server Error',
                'message' => $exception->getMessage(),
            ])
        );
    }
}
EOF

# --------------------------------------------------
# App Exception Handler
# --------------------------------------------------

echo "==> Creating app/Exceptions/Handler.php"

cat > app/Exceptions/Handler.php <<'EOF'
<?php

namespace App\Exceptions;

use Framework\Exceptions\ExceptionHandler;

class Handler extends ExceptionHandler
{
}
EOF

# --------------------------------------------------
# Hello Controller
# --------------------------------------------------

echo "==> Creating HelloController.php"

cat > app/Controllers/HelloController.php <<'EOF'
<?php

namespace App\Controllers;

use Framework\Request;

class HelloController
{
    public function index(Request $request): array
    {
        return [
            'message' => 'Hello World',
            'method' => $request->method(),
            'path' => $request->path(),
        ];
    }
}
EOF

# --------------------------------------------------
# Configuration
# --------------------------------------------------

echo "==> Creating config/app.php"

cat > config/app.php <<'EOF'
<?php

return [
    'name' => getenv('APP_NAME') ?: 'Swoole App',

    'debug' => filter_var(
        getenv('APP_DEBUG') ?: false,
        FILTER_VALIDATE_BOOL
    ),

    'timezone' => getenv('APP_TIMEZONE') ?: 'UTC',
];
EOF

# --------------------------------------------------
# Provider
# --------------------------------------------------

echo "==> Creating AppProvider.php"

cat > providers/AppProvider.php <<'EOF'
<?php

namespace App\Providers;

use Framework\Application;

class AppProvider
{
    public function register(Application $app): void
    {
        //
    }

    public function boot(Application $app): void
    {
        //
    }
}
EOF

# --------------------------------------------------
# Routes
# --------------------------------------------------

echo "==> Creating routes.php"

cat > start/routes.php <<'EOF'
<?php

use App\Controllers\HelloController;
use Framework\Router;

$router = $app->container()->make(Router::class);

$router->get(
    '/hello',
    [HelloController::class, 'index']
);
EOF

# --------------------------------------------------
# Kernel
# --------------------------------------------------

echo "==> Creating kernel.php"

cat > start/kernel.php <<'EOF'
<?php

use App\Exceptions\Handler;
use Framework\Exceptions\ExceptionHandler;
use Framework\Router;

$app->container()->singleton(
    Router::class,
    fn () => new Router()
);

$app->container()->singleton(
    ExceptionHandler::class,
    fn () => new Handler()
);

require $app->basePath('start/routes.php');
EOF

# --------------------------------------------------
# Commands
# --------------------------------------------------

echo "==> Creating commands"

cat > commands/HelloCommand.php <<'EOF'
<?php

namespace App\Commands;

class HelloCommand
{
    public function handle(): void
    {
        echo "Hello from Swoole command!\n";
    }
}
EOF

cat > commands/index.php <<'EOF'
<?php

return [];
EOF

# --------------------------------------------------
# CLI
# --------------------------------------------------

echo "==> Creating cli.php"

cat > cli.php <<'EOF'
<?php

require __DIR__ . '/vendor/autoload.php';

echo "Swoole CLI\n";
echo "-----------\n";
echo "Commands will be loaded here.\n";
EOF

# --------------------------------------------------
# Server
# --------------------------------------------------

echo "==> Creating server.php"

cat > server.php <<'EOF'
<?php

require __DIR__ . '/vendor/autoload.php';

use Framework\Application;
use Swoole\Http\Server;

$app = new Application(__DIR__);

$app->boot();

$server = new Server(
    '127.0.0.1',
    9501
);

$server->set([
    'worker_num' => 1,
]);

$server->on(
    'start',
    function (Server $server) {
        echo "Swoole server started:\n";
        echo "http://127.0.0.1:9501\n";
    }
);

$server->on(
    'request',
    function ($request, $response) use ($app) {
        $app->handle($request, $response);
    }
);

$server->start();
EOF

# --------------------------------------------------
# Test
# --------------------------------------------------

echo "==> Creating functional test"

cat > tests/functional/hello_world_test.php <<'EOF'
<?php

$url = 'http://127.0.0.1:9501/hello';

$result = file_get_contents($url);

$data = json_decode($result, true);

assert(
    $data['message'] === 'Hello World'
);

assert(
    $data['path'] === '/hello'
);

echo "Hello World test: OK\n";
EOF

# --------------------------------------------------
# Autoload
# --------------------------------------------------

echo "==> Generating Composer autoload"

composer dump-autoload

# --------------------------------------------------
# Finish
# --------------------------------------------------

echo
echo "======================================"
echo " Swoole project created successfully"
echo "======================================"
echo
echo "Project:"
echo "  $PROJECT_DIR/"
echo
echo "Start server:"
echo "  cd $PROJECT_DIR"
echo "  php server.php"
echo
echo "Test:"
echo "  curl http://127.0.0.1:9501/hello"
echo
echo "Expected:"
echo '  {"message":"Hello World","method":"GET","path":"/hello"}'
echo
