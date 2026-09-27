#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="roadrunner"

echo "======================================"
echo " Creating RoadRunner mini-framework"
echo "======================================"

# --------------------------------------------------
# Dependencies
# --------------------------------------------------

command -v php >/dev/null 2>&1 || {
    echo "ERROR: PHP is not installed."
    exit 1
}

command -v composer >/dev/null 2>&1 || {
    echo "ERROR: Composer is not installed."
    exit 1
}

echo "PHP:      $(php -v | head -n 1)"
echo "Composer: $(composer --version | head -n 1)"
echo

# --------------------------------------------------
# Directories
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
src/Exceptions,
src/Middleware,
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
  "name": "benchmark/roadrunner",
  "description": "Minimal AdonisJS-inspired framework running on RoadRunner",
  "type": "project",
  "require": {
    "php": "^8.2",
    "spiral/roadrunner": "^2025.1",
    "nyholm/psr7": "^1.8",
    "nyholm/psr7-server": "^1.1"
  },
  "autoload": {
    "psr-4": {
      "App\\": "app/",
      "Framework\\": "src/"
    }
  },
  "scripts": {
    "server": "rr serve -c .rr.yaml"
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

use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Message\ResponseInterface;
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

    public function handlePsr7(
        ServerRequestInterface $request
    ): ResponseInterface {
        try {
            $router = $this->container->make(Router::class);

            return $router->dispatch($request);
        } catch (Throwable $exception) {
            $handler = $this->container->make(
                Exceptions\ExceptionHandler::class
            );

            return $handler->handle($exception);
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

use Psr\Http\Message\ServerRequestInterface;

class Request
{
    public function __construct(
        private readonly ServerRequestInterface $request
    ) {
    }

    public function method(): string
    {
        return $this->request->getMethod();
    }

    public function path(): string
    {
        return $this->request
            ->getUri()
            ->getPath();
    }

    public function header(string $name): ?string
    {
        return $this->request
            ->getHeaderLine($name) ?: null;
    }

    public function query(
        string $key,
        mixed $default = null
    ): mixed {
        $query = $this->request->getQueryParams();

        return $query[$key] ?? $default;
    }

    public function all(): array
    {
        return $this->request->getQueryParams();
    }

    public function raw(): ServerRequestInterface
    {
        return $this->request;
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

use Nyholm\Psr7\Response as PsrResponse;
use Psr\Http\Message\ResponseInterface;

class Response
{
    public static function json(
        array $data,
        int $status = 200
    ): ResponseInterface {
        return new PsrResponse(
            $status,
            [
                'Content-Type' => 'application/json',
            ],
            json_encode(
                $data,
                JSON_UNESCAPED_UNICODE |
                JSON_UNESCAPED_SLASHES
            )
        );
    }

    public static function text(
        string $content,
        int $status = 200
    ): ResponseInterface {
        return new PsrResponse(
            $status,
            [
                'Content-Type' => 'text/plain; charset=utf-8',
            ],
            $content
        );
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

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
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
        ServerRequestInterface $request
    ): ResponseInterface {
        $method = $request->getMethod();
        $path = $request->getUri()->getPath();

        $handler = $this->routes[$method][$path] ?? null;

        if ($handler === null) {
            return Response::json([
                'error' => 'Not Found',
                'status' => 404,
            ], 404);
        }

        [$controllerClass, $action] = $handler;

        $controller = new $controllerClass();

        if (!method_exists($controller, $action)) {
            throw new RuntimeException(
                "Action [$action] not found on [$controllerClass]"
            );
        }

        $frameworkRequest = new Request($request);

        $result = $controller->$action(
            $frameworkRequest
        );

        if ($result instanceof ResponseInterface) {
            return $result;
        }

        if (is_array($result)) {
            return Response::json($result);
        }

        return Response::text((string) $result);
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

use Nyholm\Psr7\Response;
use Psr\Http\Message\ResponseInterface;
use Throwable;

class ExceptionHandler
{
    public function handle(
        Throwable $exception
    ): ResponseInterface {
        return new Response(
            500,
            [
                'Content-Type' => 'application/json',
            ],
            json_encode([
                'error' => 'Internal Server Error',
                'message' => $exception->getMessage(),
            ])
        );
    }
}
EOF

# --------------------------------------------------
# Application Exception Handler
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
# Controller
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
# Config
# --------------------------------------------------

echo "==> Creating config/app.php"

cat > config/app.php <<'EOF'
<?php

return [
    'name' => getenv('APP_NAME') ?: 'RoadRunner App',

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
        echo "Hello from RoadRunner command!\n";
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

echo "RoadRunner CLI\n";
echo "---------------\n";
echo "Commands will be loaded here.\n";
EOF

# --------------------------------------------------
# RoadRunner worker
# --------------------------------------------------

echo "==> Creating app.php"

cat > app.php <<'EOF'
<?php

require __DIR__ . '/vendor/autoload.php';

use Framework\Application;
use Nyholm\Psr7\Factory\Psr17Factory;
use Spiral\RoadRunner\Worker;
use Spiral\RoadRunner\Http\PSR7Worker;
use Throwable;

$app = new Application(__DIR__);

$app->boot();

$factory = new Psr17Factory();

$worker = Worker::create();

$psr7Worker = new PSR7Worker(
    $worker,
    $factory,
    $factory,
    $factory
);

while (true) {
    try {
        $request = $psr7Worker->waitRequest();

        if ($request === null) {
            break;
        }

        $response = $app->handlePsr7($request);

        $psr7Worker->respond($response);
    } catch (Throwable $exception) {
        $psr7Worker->respond(
            new \Nyholm\Psr7\Response(
                500,
                [
                    'Content-Type' => 'application/json',
                ],
                json_encode([
                    'error' => 'Worker Error',
                    'message' => $exception->getMessage(),
                ])
            )
        );
    }
}
EOF

# --------------------------------------------------
# RoadRunner configuration
# --------------------------------------------------

echo "==> Creating .rr.yaml"

cat > .rr.yaml <<'EOF'
version: "3"

server:
  command: "php app.php"

http:
  address: "127.0.0.1:8080"

  pool:
    num_workers: 1
    max_jobs: 0
    allocate_timeout: 60s
    destroy_timeout: 60s

logs:
  mode: development
  level: info
EOF

# --------------------------------------------------
# Functional test
# --------------------------------------------------

echo "==> Creating functional test"

cat > tests/functional/hello_world_test.php <<'EOF'
<?php

$url = 'http://127.0.0.1:8080/hello';

$result = file_get_contents($url);

$data = json_decode($result, true);

assert(
    $data['message'] === 'Hello World'
);

assert(
    $data['method'] === 'GET'
);

assert(
    $data['path'] === '/hello'
);

echo "Hello World test: OK\n";
EOF

# --------------------------------------------------
# Composer install
# --------------------------------------------------

echo "==> Installing dependencies"

composer install

echo "==> Generating autoload"

composer dump-autoload

# --------------------------------------------------
# Finish
# --------------------------------------------------

echo
echo "======================================"
echo " RoadRunner project created"
echo "======================================"
echo
echo "Start:"
echo
echo "  cd $PROJECT_DIR"
echo "  ./vendor/bin/rr serve -c .rr.yaml"
echo
echo "Test:"
echo
echo "  curl http://127.0.0.1:8080/hello"
echo
echo "Expected:"
echo
echo '  {"message":"Hello World","method":"GET","path":"/hello"}'
echo
