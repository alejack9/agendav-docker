<?php

return [
    'csrf.secret' => 'ci-smoke-test-only-secret-change-in-real-deployments',
    'db.options' => [
        'driver' => 'pdo_mysql',
        'host' => 'db',
        'dbname' => 'agendav',
        'user' => 'agendav',
        'password' => 'agendav',
        'charset' => 'utf8mb4',
    ],
    'session.storage.options' => [
        'cookie_secure' => false,
    ],
];
