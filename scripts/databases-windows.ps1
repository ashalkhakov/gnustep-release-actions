# databases.sh on Windows: the database servers a repository's tests run
# against, on the runner itself (its Docker runs Windows containers only),
# on the same ports, users, passwords and databases, named in the same
# variables (GITHUB_ENV):
#
#   postgres   PostgreSQL 17, the image's   127.0.0.1:5432   POSTGRES_URL
#   mysql      MySQL 8.0, the image's       127.0.0.1:3306   MYSQL_URL
#   mariadb    MariaDB 11.4, downloaded     127.0.0.1:3307   MARIADB_URL
#
# Each has the user postgres or root, the password "test", and a database
# named "test".
#
#   $env:DATABASES = "postgres mariadb"; databases-windows.ps1
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:RUNNER_TEMP 'databases'
New-Item -ItemType Directory -Force $root | Out-Null

function Wait-Until([string]$what, [scriptblock]$ready) {
  for ($i = 0; $i -lt 90; $i++) {
    try { if (& $ready) { return } } catch { }
    Start-Sleep -Seconds 2
  }
  throw "$what did not start"
}

foreach ($db in ($env:DATABASES -split '\s+' | Where-Object { $_ })) {
  switch ($db) {
    'postgres' {
      Set-Service postgresql-x64-17 -StartupType Manual
      Start-Service postgresql-x64-17
      $psql = Join-Path $env:PGBIN 'psql.exe'
      $env:PGPASSWORD = 'root'
      Wait-Until 'postgres' { & $psql -h 127.0.0.1 -U postgres -c 'SELECT 1' 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
      & $psql -h 127.0.0.1 -U postgres -c "ALTER USER postgres PASSWORD 'test'" | Out-Null
      $env:PGPASSWORD = 'test'
      & $psql -h 127.0.0.1 -U postgres -c 'CREATE DATABASE test' | Out-Null
      $url = 'postgresql://postgres:test@127.0.0.1:5432/test'
    }
    'mysql' {
      $mysqld = (Get-Command mysqld.exe).Source
      $bin = Split-Path $mysqld
      $data = Join-Path $root 'mysql'
      & $mysqld --initialize-insecure --datadir="$data" 2>&1 | Out-Null
      Start-Process -FilePath $mysqld -ArgumentList "--datadir=`"$data`"", '--port=3306', '--bind-address=127.0.0.1' -WindowStyle Hidden
      $mysql = Join-Path $bin 'mysql.exe'
      Wait-Until 'mysql' { & $mysql -h 127.0.0.1 -P 3306 -uroot -e 'SELECT 1' 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
      & $mysql -h 127.0.0.1 -P 3306 -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'test'; CREATE DATABASE test;"
      $url = 'mysql://root:test@127.0.0.1:3306/test'
    }
    'mariadb' {
      $version = '11.4.5'
      $zip = Join-Path $root 'mariadb.zip'
      Invoke-WebRequest "https://archive.mariadb.org/mariadb-$version/winx64-packages/mariadb-$version-winx64.zip" -OutFile $zip
      Expand-Archive $zip -DestinationPath $root -Force
      $bin = Join-Path $root "mariadb-$version-winx64\bin"
      $data = Join-Path $root 'mariadb-data'
      & (Join-Path $bin 'mariadb-install-db.exe') "--datadir=$data" '--port=3307' '--password=test' 2>&1 | Out-Null
      Start-Process -FilePath (Join-Path $bin 'mariadbd.exe') -ArgumentList "--defaults-file=`"$data\my.ini`"", '--bind-address=127.0.0.1' -WindowStyle Hidden
      $mariadb = Join-Path $bin 'mariadb.exe'
      Wait-Until 'mariadb' { & $mariadb -h 127.0.0.1 -P 3307 -uroot -ptest -e 'SELECT 1' 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
      & $mariadb -h 127.0.0.1 -P 3307 -uroot -ptest -e 'CREATE DATABASE test'
      $url = 'mysql://root:test@127.0.0.1:3307/test'
    }
    default { throw "databases: no '$db' (postgres, mysql, mariadb)" }
  }
  "$($db.ToUpper())_URL=$url" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  Write-Output "${db}: $url"
}
