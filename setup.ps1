# Reuse the shared venv by default, or use the directory supplied by the caller.
param([string]$VenvDir = "$PSScriptRoot\.venv")

$ErrorActionPreference = "Stop"
# Keep relative paths and Git commands anchored at the platform repository root.
Push-Location $PSScriptRoot
try {
    # Initialize every nested submodule, including on clones that skipped them.
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        throw "git submodule update failed with exit code $LASTEXITCODE"
    }

    $VenvDir = [System.IO.Path]::GetFullPath($VenvDir)
    # Read the Python major.minor version used by the shared tooling package.
    $PythonVersion = (Get-Content ".\LondonDataServices.DataPlatformTooling\PYTHON_VERSION" -Raw).Trim()
    if (-not $PythonVersion) {
        throw "PYTHON_VERSION must contain a Python major.minor version"
    }

    $VenvPython = Join-Path $VenvDir "Scripts\python.exe"
    $ExistingPythonVersion = ""
    # Detect the existing interpreter version; a missing or invalid venv is rebuilt.
    if (Test-Path $VenvPython) {
        $ExistingPythonVersion = & $VenvPython -c "import sys; print('{}.{}'.format(sys.version_info.major, sys.version_info.minor))"
        if ($LASTEXITCODE -ne 0) {
            $ExistingPythonVersion = ""
        }
    }

    # Recreate only when the venv is absent or its Python version differs from the pin.
    if ((Test-Path $VenvDir) -and ($ExistingPythonVersion -ne $PythonVersion)) {
        Remove-Item -LiteralPath $VenvDir -Recurse -Force
    }

    # Create the pinned interpreter, activate the venv, and install the tooling package.
    if (-not (Test-Path $VenvDir)) {
        py "-$PythonVersion" -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) {
            throw "Creating the Python venv failed with exit code $LASTEXITCODE"
        }
    }

    # Install the shared setup commands, then run them from the repository root.
    $VenvPython = Join-Path $VenvDir "Scripts\python.exe"
    . (Join-Path $VenvDir "Scripts\Activate.ps1")
    & $VenvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw "Upgrading pip failed with exit code $LASTEXITCODE"
    }
    & $VenvPython -m pip install -e ".\LondonDataServices.DataPlatformTooling"
    if ($LASTEXITCODE -ne 0) {
        throw "Installing dbt-platform-tooling failed with exit code $LASTEXITCODE"
    }

    install-infisical
    if ($LASTEXITCODE -ne 0) {
        throw "install-infisical failed with exit code $LASTEXITCODE"
    }

    attach-precommit-hooks
    if ($LASTEXITCODE -ne 0) {
        throw "attach-precommit-hooks failed with exit code $LASTEXITCODE"
    }
}
finally {
    # Restore the caller's original working directory, including on failure.
    Pop-Location
}
