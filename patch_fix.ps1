# Fix: sub-tab bar not showing because return statements skip it
# Run: powershell -ExecutionPolicy Bypass -File patch_fix.ps1

$file = "index.html"
$html = [System.IO.File]::ReadAllText((Resolve-Path $file).Path)

$changes = 0

# Find the two return statements in tFood that skip the sub-tab bar html variable
# They return raw strings instead of html+'...'

# Fix 1: the "no meals" return
$old1 = "if(!allMeals.length){`n    return'<div"
$new1 = "if(!allMeals.length){`n    return html+'<div"
if ($html.Contains($old1)) {
    $html = $html.Replace($old1, $new1)
    $changes++
    Write-Host "[1] Fixed no-meals return to include sub-tab bar"
}

# Fix 2: the main food content return
$old2 = "  return'<div style=`"font-size:15px;font-weight:600;color:var(--text3);font-family:var(--font);text-transform:uppercase;letter-spacing:.5px;padding:6px 4px 6px;`">Food Plan</div>'"
$new2 = "  return html+'<div style=`"font-size:15px;font-weight:600;color:var(--text3);font-family:var(--font);text-transform:uppercase;letter-spacing:.5px;padding:6px 4px 6px;`">Food Plan</div>'"
if ($html.Contains($old2)) {
    $html = $html.Replace($old2, $new2)
    $changes++
    Write-Host "[2] Fixed main food return to include sub-tab bar"
}

if ($changes -eq 0) {
    Write-Host "No changes needed - returns may already be fixed."
    Write-Host "Checking... does file contain 'return html+' near 'Food Plan'?"
    if ($html.Contains("return html+'<div")) {
        Write-Host "Yes - looks already fixed!"
    } else {
        Write-Host "No - something unexpected. Check manually."
    }
} else {
    [System.IO.File]::WriteAllText((Resolve-Path $file).Path, $html)
    $newSize = (Get-Item $file).Length
    Write-Host "`nDone! $changes fixes applied. File size: $([math]::Round($newSize/1024))KB"
    Write-Host "Now run push.bat to deploy."
}
