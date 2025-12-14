<!DOCTYPE html>
<html>
<head>
<title>Welcome to LAMP Stack!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
        background-color: #f0f0f0;
        color: #333;
        padding-top: 50px;
    }
    h1 {
        font-size: 2em;
        margin-bottom: 0.5em;
    }
    p {
        line-height: 1.5;
    }
    .info {
        background-color: #fff;
        padding: 20px;
        border-radius: 5px;
        box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        margin-top: 20px;
    }
    ul {
        list-style-type: none;
        padding: 0;
    }
    li {
        padding: 5px 0;
        border-bottom: 1px solid #eee;
    }
    li:last-child {
        border-bottom: none;
    }
    .label {
        font-weight: bold;
        display: inline-block;
        width: 120px;
    }
</style>
</head>
<body>
    <h1>Welcome to LAMP Stack!</h1>
    <p>If you see this page, the LAMP stack is successfully installed and working.</p>

    <div class="info">
        <h2>Stack Information</h2>
        <ul>
            <li><span class="label">Web Server:</span> <?= $_SERVER['SERVER_SOFTWARE']; ?></li>
            <li><span class="label">PHP Version:</span> <?= phpversion(); ?></li>
        </ul>
    </div>

    <p><em>Thank you for using this docker stack.</em></p>
</body>
</html>
