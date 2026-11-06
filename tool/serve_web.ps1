# Server statis kecil untuk pratinjau hasil `flutter build web`.
# Pakai: powershell -ExecutionPolicy Bypass -File tool\serve_web.ps1 [-Port 8088]
param(
    [int]$Port = 8088,
    [string]$Root = '',
    # Daftarkan juga alamat jaringan lokal supaya HP di Wi-Fi yang sama bisa
    # mengunduh APK dari server ini. Butuh izin HttpListener (biasanya admin).
    [switch]$AllInterfaces
)

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\web'
}
if (-not (Test-Path $Root)) {
    Write-Error "Folder build tidak ada: $Root. Jalankan dulu: flutter build web --release"
    exit 1
}
$Root = (Resolve-Path $Root).Path

$mime = @{
    '.html'  = 'text/html; charset=utf-8'
    '.js'    = 'text/javascript; charset=utf-8'
    '.mjs'   = 'text/javascript; charset=utf-8'
    '.json'  = 'application/json; charset=utf-8'
    '.css'   = 'text/css; charset=utf-8'
    '.png'   = 'image/png'
    '.jpg'   = 'image/jpeg'
    '.jpeg'  = 'image/jpeg'
    '.gif'   = 'image/gif'
    '.svg'   = 'image/svg+xml'
    '.ico'   = 'image/x-icon'
    '.ttf'   = 'font/ttf'
    '.otf'   = 'font/otf'
    '.woff'  = 'font/woff'
    '.woff2' = 'font/woff2'
    '.wasm'  = 'application/wasm'
    '.map'   = 'application/json; charset=utf-8'
    '.txt'   = 'text/plain; charset=utf-8'
    '.webmanifest' = 'application/manifest+json'
}

$listener = New-Object System.Net.HttpListener
if ($AllInterfaces) {
    $listener.Prefixes.Add("http://+:$Port/")
} else {
    $listener.Prefixes.Add("http://localhost:$Port/")
}
try {
    $listener.Start()
} catch {
    if ($AllInterfaces) {
        Write-Error ("Tidak bisa membuka port ${Port} untuk jaringan lokal: " +
            "$($_.Exception.Message)`n" +
            "Jalankan PowerShell sebagai Administrator, lalu ulangi. " +
            "Tanpa itu server hanya bisa dibuka dari komputer ini.")
    } else {
        Write-Error "Tidak bisa membuka port ${Port}: $($_.Exception.Message)"
    }
    exit 1
}

Write-Host "FishGuard web  ->  http://localhost:$Port/"
Write-Host "Folder         ->  $Root"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        try {
            $path = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
            if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }

            $full = [System.IO.Path]::GetFullPath((Join-Path $Root $path.TrimStart('/')))
            if (-not $full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
                $res.StatusCode = 403
                $res.Close()
                continue
            }
            if (Test-Path $full -PathType Container) {
                $full = Join-Path $full 'index.html'
            }
            if (-not (Test-Path $full -PathType Leaf)) {
                # Rute tak dikenal -> kirim index.html (aplikasi satu halaman).
                $full = Join-Path $Root 'index.html'
                if (-not (Test-Path $full -PathType Leaf)) {
                    $res.StatusCode = 404
                    $res.Close()
                    continue
                }
            }

            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
            $res.Headers['Cache-Control'] = 'no-cache'
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $res.ContentLength64 = $bytes.Length
            if ($req.HttpMethod -ne 'HEAD') {
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $res.StatusCode = 200
            Write-Host ("{0} {1} -> {2}" -f $req.HttpMethod, $path, $res.StatusCode)
        } catch {
            Write-Host "Gagal melayani $($req.Url): $($_.Exception.Message)"
            try { $res.StatusCode = 500 } catch { }
        } finally {
            try { $res.OutputStream.Close() } catch { }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
