<?php
// Readiness without creating a missing database or applying migrations.
declare(strict_types=1);
try {
    $path = getenv('CLOG_DB');
    if (!$path || !is_file($path) || !file_exists('/run/clog/php.sock')) exit(1);
    require '/opt/clog/server/standalone/bootstrap.php';
    \Clog\Standalone\Schema::requireReady(new \Eleph\SQLite\Database($path));
} catch (Throwable $error) {
    fwrite(STDERR, "Clog is not ready.\n");
    exit(1);
}
