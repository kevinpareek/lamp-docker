<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 Not Found</title>
    <style>
        body {
            background-color: #f0f2f5;
            color: #333;
            font-family: 'Roboto', Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
        h1 {
            font-size: 6em;
            margin: 0;
            color: #715dbb;
        }
        h2 {
            font-size: 2em;
            margin: 10px 0;
        }
        p {
            font-size: 1.2em;
            color: #666;
        }
        a {
            margin-top: 20px;
            padding: 10px 20px;
            background-color: #715dbb;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            transition: background-color 0.3s;
        }
        a:hover {
            background-color: #5a4a9b;
        }
    </style>
</head>
<body>
    <h1>404</h1>
    <h2>Page Not Found</h2>
    <p>The page you are looking for might have been removed, had its name changed, or is temporarily unavailable.</p>
    <a href="/">Go to Homepage</a>
</body>
</html>

echo '<hr/>';
echo '<a href="/">Back</a>';