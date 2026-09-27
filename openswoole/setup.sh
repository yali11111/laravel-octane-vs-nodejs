#!/usr/bin/env bash

set -e

PROJECT_DIR="swoole"

echo "==> Creating $PROJECT_DIR"

mkdir -p "$PROJECT_DIR"/{app/Controllers,app/Exceptions,config,providers,src,start,tests/functional}

cd "$PROJECT_DIR"

echo "==> Creating composer.json"

cat > composer.json <<'EOF'
{
  "name": "benchmark/swoole",
  "type": "project",
  "require": {
    "php": "^8.2"
  },
  "autoload": {
    "psr-4": {
      "App\\": "app/",
      "Framework\\": "src/"
    }
  }
}
EOF

echo "==> Creating Application.php"

cat > src/Application.php <<'EOF'
<?php

namespace Framework;

class Application
{
    private Container $container;

    public function __construct(
        private string $basePath
    ) {
        $this->container = new Container();
    }

    public function boot(): void
    {
        require $this->basePath . '/start/kernel.php';
    }

    public function handle($request, $response): void
    {
        $router = $this->container->make(Router::class);

        $router->dispatch($request, $response);
    }

    public function container(): Container
    {
        return $this->container;
    }

    public function basePath(string $path = ''): string
    {
        return $this->basePath . ($path ? '/' . $path : '');
    }
}
EOF

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

echo "==> Creating Router.php"

cat > src/Router.php <<'EOF'
<?php

namespace Framework;

class Router
{
    private array $routes = [];

    public function get(
        string $path,
        array $handler
    ): void {
        $this->routes['GET'][$path] = $handler;
    }

    public function dispatch($request, $response): void
    {
        $method = $request->server['request_method'] ?? 'GET';
        $path = $request->server['request_uri'] ?? '/';

        $handler = $this->routes[$method][$path] ?? null;

        if ($handler === null) {
            $response->status(404);
            $response->end('Not Found');
            return;
        }

        [$controller, $action] = $handler;

        $instance = new $controller();

        $result = $instance->$action();

        $response->header(
            'Content-Type',
            'application/json'
        );

        $response->end(
            json_encode($result)
        );
    }
}
EOF

echo "==> Creating HelloController.php"

cat > app/Controllers/HelloController.php <<'EOF'
<?php

namespace App\Controllers;

class HelloController
{
    public function index(): array
    {
        return [
            'message' => 'Hello World',
        ];
    }
}
EOF

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

echo "==> Creating kernel.php"

cat > start/kernel.php <<'EOF'
<?php

use Framework\Router;

$app->container()->singleton(
    Router::class,
    fn () => new Router()
);

require $app->basePath('start/routes.php');
EOF

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

$server->on(
    'request',
    function ($request, $response) use ($app) {
        $app->handle($request, $response);
    }
);

echo "Swoole server started on http://127.0.0.1:9501\n";

$server->start();
EOF

echo "==> Installing dependencies"

composer require openswoole/core

echo "==> Dumping autoload"

composer dump-autoload

echo
echo "======================================"
echo " Swoole mini-framework created!"
echo "======================================"
echo
echo "Run:"
echo
echo "  php server.php"
echo
echo "Then:"
echo
echo "  curl http://127.0.0.1:9501/hello"
echo
