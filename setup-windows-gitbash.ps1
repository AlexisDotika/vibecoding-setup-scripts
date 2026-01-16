#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de setup automatique pour la formation Vibecoding (Windows avec Git Bash)

.DESCRIPTION
    Ce script installe et configure tout l'environnement necessaire.
    Utilise Git Bash au lieu de WSL pour une compatibilite maximale.

.PARAMETER Step
    Numero de l'etape a laquelle commencer (1-10)

.PARAMETER Reset
    Remet la progression a zero et recommence depuis le debut

.EXAMPLE
    .\setup-windows-gitbash.ps1
    .\setup-windows-gitbash.ps1 -Step 5
    .\setup-windows-gitbash.ps1 -Reset

.NOTES
    Auteur: Formation Vibecoding
    Version: 1.0
#>

param(
    [int]$Step = 0,
    [switch]$Reset,
    [switch]$Help
)

# Configuration
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$PROGRESS_FILE = "$env:USERPROFILE\.vibecoding_setup_progress"
$SCRIPT_VERSION = "1.0"

# Variables globales pour le repo
$script:RepoUrl = ""
$script:RepoName = ""
$script:GitBashPath = ""

# ============================================
# FONCTIONS UTILITAIRES
# ============================================

function Write-Step {
    param($msg)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-SubStep {
    param($msg)
    Write-Host "`n>> $msg" -ForegroundColor White
}

function Write-Success {
    param($msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Write-WarningMsg {
    param($msg)
    Write-Host "[!] $msg" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param($msg)
    Write-Host "[X] $msg" -ForegroundColor Red
}

function Write-Info {
    param($msg)
    Write-Host "    $msg" -ForegroundColor Gray
}

function Write-Manual {
    param($msg)
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Magenta
    Write-Host "  ACTION MANUELLE REQUISE" -ForegroundColor Magenta
    Write-Host "--------------------------------------------" -ForegroundColor Magenta
    Write-Host $msg -ForegroundColor White
    Write-Host ""
}

function Wait-ForUser {
    param($msg = "Appuyez sur Entree une fois termine...")
    Write-Host ""
    Read-Host $msg
}

function Show-Banner {
    Clear-Host
    Write-Host @"

 __     _____ ____  _____ ____ ___  ____ ___ _   _  ____
 \ \   / /_ _| __ )| ____/ ___/ _ \|  _ \_ _| \ | |/ ___|
  \ \ / / | ||  _ \|  _|| |  | | | | | | | ||  \| | |  _
   \ V /  | || |_) | |__| |__| |_| | |_| | || |\  | |_| |
    \_/  |___|____/|_____\____\___/|____/___|_| \_|\____|

       Setup Windows (Git Bash) - v$SCRIPT_VERSION

"@ -ForegroundColor Magenta
}

function Show-Help {
    Show-Banner
    Write-Host "UTILISATION:" -ForegroundColor Yellow
    Write-Host "  .\setup-windows-gitbash.ps1              Lancer avec menu interactif"
    Write-Host "  .\setup-windows-gitbash.ps1 -Step 5      Demarrer a l'etape 5"
    Write-Host "  .\setup-windows-gitbash.ps1 -Reset       Repartir de zero"
    Write-Host "  .\setup-windows-gitbash.ps1 -Help        Afficher cette aide"
    Write-Host ""
    Write-Host "ETAPES:" -ForegroundColor Yellow
    Write-Host "  1. Compte Anthropic et abonnement Max"
    Write-Host "  2. Installation de Git for Windows (avec Git Bash)"
    Write-Host "  3. Installation de Node.js"
    Write-Host "  4. Installation de GitHub CLI et Claude Code"
    Write-Host "  5. Connexion a Claude Code"
    Write-Host "  6. Compte GitHub"
    Write-Host "  7. Configuration Git et cle SSH"
    Write-Host "  8. Ajout cle SSH a GitHub + creation repository"
    Write-Host "  9. Cloner le repository"
    Write-Host "  10. Configuration Supabase + MCP"
    Write-Host ""
}

# ============================================
# GESTION DE LA PROGRESSION
# ============================================

function Save-Progress {
    param([int]$StepNum)
    @{
        Step = $StepNum
        RepoUrl = $script:RepoUrl
        RepoName = $script:RepoName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    } | ConvertTo-Json | Set-Content -Path $PROGRESS_FILE
}

function Get-SavedProgress {
    if (Test-Path $PROGRESS_FILE) {
        try {
            $progress = Get-Content $PROGRESS_FILE | ConvertFrom-Json
            return $progress
        } catch {
            return $null
        }
    }
    return $null
}

function Reset-Progress {
    if (Test-Path $PROGRESS_FILE) {
        Remove-Item $PROGRESS_FILE -Force
    }
    Write-Success "Progression reininitialisee"
}

# ============================================
# FONCTIONS UTILITAIRES GIT BASH
# ============================================

function Get-GitBashPath {
    $possiblePaths = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles(x86)\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Invoke-GitBash {
    param([string]$Script)

    if (-not $script:GitBashPath) {
        $script:GitBashPath = Get-GitBashPath
    }

    if (-not $script:GitBashPath) {
        throw "Git Bash n'est pas installe"
    }

    $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
    $Script | Set-Content -Path $tempScript -Encoding UTF8

    try {
        $result = & $script:GitBashPath --login -c "source '$($tempScript -replace '\\', '/')'" 2>&1
        return $result
    } finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

# ============================================
# GESTION DES ERREURS
# ============================================

function Invoke-WithRetry {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    while ($true) {
        try {
            & $Action
            return $true
        } catch {
            Write-ErrorMsg "Erreur: $_"
            Write-Host ""
            Write-Host "Que voulez-vous faire ?" -ForegroundColor Yellow
            Write-Host "  [R] Reessayer"
            Write-Host "  [S] Passer cette etape"
            Write-Host "  [Q] Quitter le script"
            Write-Host ""

            $choice = Read-Host "Votre choix (R/S/Q)"

            switch ($choice.ToUpper()) {
                "R" {
                    Write-Info "Nouvelle tentative..."
                    continue
                }
                "S" {
                    Write-WarningMsg "Etape passee"
                    return $false
                }
                "Q" {
                    Write-Host "`nProgression sauvegardee. Vous pourrez reprendre plus tard." -ForegroundColor Yellow
                    exit 0
                }
                default {
                    Write-Info "Choix non reconnu, nouvelle tentative..."
                    continue
                }
            }
        }
    }
}

# ============================================
# MENU INTERACTIF
# ============================================

function Show-Menu {
    param([int]$CurrentStep = 1)

    Show-Banner

    $savedProgress = Get-SavedProgress

    Write-Host "Ce script va vous guider pour installer tout le necessaire." -ForegroundColor White
    Write-Host "Cette version utilise Git Bash (pas WSL)." -ForegroundColor Yellow
    Write-Host "Duree estimee : 15-20 minutes`n" -ForegroundColor Gray

    if ($savedProgress -and $savedProgress.Step -gt 1) {
        Write-Host "Progression sauvegardee detectee : Etape $($savedProgress.Step)/10" -ForegroundColor Green
        Write-Host "($($savedProgress.Timestamp))" -ForegroundColor Gray
        Write-Host ""
    }

    Write-Host "MENU - Choisissez par ou commencer :" -ForegroundColor Yellow
    Write-Host ""

    $steps = @(
        "Compte Anthropic et abonnement Max",
        "Installation Git for Windows (Git Bash)",
        "Installation Node.js",
        "Installation GitHub CLI et Claude Code",
        "Connexion a Claude Code",
        "Compte GitHub",
        "Configuration Git et cle SSH",
        "Ajout cle SSH a GitHub + creation repository",
        "Cloner le repository",
        "Configuration Supabase + MCP"
    )

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $num = $i + 1
        $status = ""
        if ($savedProgress -and $num -lt $savedProgress.Step) {
            $status = " [OK]"
            Write-Host "  $num. $($steps[$i])$status" -ForegroundColor Green
        } elseif ($savedProgress -and $num -eq $savedProgress.Step) {
            $status = " [En cours]"
            Write-Host "  $num. $($steps[$i])$status" -ForegroundColor Yellow
        } else {
            Write-Host "  $num. $($steps[$i])" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "  0. Repartir de zero (effacer la progression)" -ForegroundColor Gray
    Write-Host ""

    $defaultChoice = 1
    if ($savedProgress -and $savedProgress.Step -gt 1) {
        $defaultChoice = $savedProgress.Step
        if ($savedProgress.RepoUrl) {
            $script:RepoUrl = $savedProgress.RepoUrl
            $script:RepoName = $savedProgress.RepoName
        }
    }

    $input = Read-Host "Votre choix [defaut: $defaultChoice]"

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $defaultChoice
    }

    $choice = [int]$input

    if ($choice -eq 0) {
        Reset-Progress
        return 1
    }

    if ($choice -lt 1 -or $choice -gt 10) {
        Write-WarningMsg "Choix invalide, demarrage a l'etape 1"
        return 1
    }

    return $choice
}

# ============================================
# VERIFICATION ADMIN
# ============================================

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================
# ETAPES D'INSTALLATION
# ============================================

function Invoke-Step1 {
    Write-Step "Etape 1/10 : Compte Anthropic et abonnement"

    Write-Manual @"
Vous devez creer un compte Anthropic et prendre l'abonnement Max :

  1. Allez sur : https://claude.ai
  2. Creez un compte (ou connectez-vous)
  3. Prenez l'abonnement MAX a 100 euros/mois
"@

    Start-Process "https://claude.ai"
    Wait-ForUser "Appuyez sur Entree une fois votre compte cree et l'abonnement Max active..."
    Write-Success "Compte Anthropic configure"
    Save-Progress 2
}

function Invoke-Step2 {
    Write-Step "Etape 2/10 : Installation de Git for Windows"

    # Verifier si Git est deja installe
    $gitPath = Get-GitBashPath
    if ($gitPath) {
        Write-Success "Git for Windows est deja installe"
        $script:GitBashPath = $gitPath
        Save-Progress 3
        return
    }

    Write-SubStep "Telechargement et installation de Git for Windows..."

    Write-Manual @"
L'installateur de Git va s'ouvrir.

Pendant l'installation, gardez les options par defaut SAUF :
  - A l'etape "Choosing the default editor" : choisissez ce que vous preferez
  - A l'etape "Adjusting the name of the initial branch" : selectionnez "main"
  - Pour le reste : cliquez sur "Next" puis "Install"
"@

    # Telecharger Git
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe"
    $gitInstaller = "$env:TEMP\GitInstaller.exe"

    Write-Info "Telechargement en cours..."
    try {
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
        Write-Success "Telechargement termine"
    } catch {
        Write-ErrorMsg "Erreur de telechargement. Telechargez manuellement depuis https://git-scm.com/download/win"
        Start-Process "https://git-scm.com/download/win"
        Wait-ForUser "Appuyez sur Entree une fois Git installe..."
        Save-Progress 3
        return
    }

    # Lancer l'installation
    Write-Info "Lancement de l'installateur..."
    Start-Process -FilePath $gitInstaller -Wait

    # Verifier l'installation
    $script:GitBashPath = Get-GitBashPath
    if ($script:GitBashPath) {
        Write-Success "Git for Windows installe avec succes"
        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
    } else {
        Write-WarningMsg "Git ne semble pas installe. Verifiez et relancez le script."
    }

    Save-Progress 3
}

function Invoke-Step3 {
    Write-Step "Etape 3/10 : Installation de Node.js"

    # Verifier si Node est deja installe
    try {
        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            Write-Success "Node.js est deja installe ($nodeVersion)"
            Save-Progress 4
            return
        }
    } catch {}

    Write-SubStep "Telechargement et installation de Node.js..."

    Write-Manual @"
L'installateur de Node.js va s'ouvrir.

  - Cliquez sur "Next" a chaque etape
  - Acceptez la licence
  - Gardez les options par defaut
  - Cliquez sur "Install" puis "Finish"
"@

    # Telecharger Node.js LTS
    $nodeUrl = "https://nodejs.org/dist/v22.13.1/node-v22.13.1-x64.msi"
    $nodeInstaller = "$env:TEMP\NodeInstaller.msi"

    Write-Info "Telechargement en cours..."
    try {
        Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeInstaller -UseBasicParsing
        Write-Success "Telechargement termine"
    } catch {
        Write-ErrorMsg "Erreur de telechargement. Telechargez manuellement depuis https://nodejs.org"
        Start-Process "https://nodejs.org"
        Wait-ForUser "Appuyez sur Entree une fois Node.js installe..."
        Save-Progress 4
        return
    }

    # Lancer l'installation
    Write-Info "Lancement de l'installateur..."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$nodeInstaller`"" -Wait

    # Rafraichir le PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Verifier l'installation
    try {
        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            Write-Success "Node.js installe avec succes ($nodeVersion)"
            Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue
        } else {
            Write-WarningMsg "Node.js ne semble pas installe. Vous devrez peut-etre redemarrer le terminal."
        }
    } catch {
        Write-WarningMsg "Impossible de verifier Node.js. Continuez et verifiez plus tard."
    }

    Save-Progress 4
}

function Invoke-Step4 {
    Write-Step "Etape 4/10 : Installation de GitHub CLI et Claude Code"

    # Installer GitHub CLI
    Write-SubStep "Installation de GitHub CLI..."

    try {
        $ghVersion = gh --version 2>$null
        if ($ghVersion) {
            Write-Success "GitHub CLI est deja installe"
        }
    } catch {
        $ghUrl = "https://github.com/cli/cli/releases/download/v2.64.0/gh_2.64.0_windows_amd64.msi"
        $ghInstaller = "$env:TEMP\GHInstaller.msi"

        Write-Info "Telechargement de GitHub CLI..."
        try {
            Invoke-WebRequest -Uri $ghUrl -OutFile $ghInstaller -UseBasicParsing
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ghInstaller`" /quiet" -Wait
            Remove-Item $ghInstaller -Force -ErrorAction SilentlyContinue

            # Rafraichir le PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            Write-Success "GitHub CLI installe"
        } catch {
            Write-WarningMsg "Erreur lors de l'installation de GitHub CLI"
        }
    }

    # Installer Claude Code
    Write-SubStep "Installation de Claude Code..."

    try {
        $claudeVersion = claude --version 2>$null
        if ($claudeVersion) {
            Write-Success "Claude Code est deja installe"
        }
    } catch {
        Write-Info "Installation via npm..."
        try {
            npm install -g @anthropic-ai/claude-code
            Write-Success "Claude Code installe"
        } catch {
            Write-ErrorMsg "Erreur lors de l'installation de Claude Code"
            Write-Info "Essayez manuellement: npm install -g @anthropic-ai/claude-code"
        }
    }

    Save-Progress 5
}

function Invoke-Step5 {
    Write-Step "Etape 5/10 : Connexion a Claude Code"

    Write-Manual @"
Vous devez maintenant connecter Claude Code a votre compte Anthropic :

  1. Ouvrez Git Bash (cherchez "Git Bash" dans le menu Demarrer)
  2. Tapez : claude
  3. Choisissez 'Claude Max (subscription)' (PAS 'API Key')
  4. Un navigateur va s'ouvrir, connectez-vous avec votre compte Anthropic
  5. Quand Claude demande les 'settings', gardez les options par defaut
  6. Posez une question simple pour verifier que ca marche
  7. Tapez /exit pour quitter Claude Code
"@

    Wait-ForUser "Appuyez sur Entree une fois connecte a Claude Code..."
    Write-Success "Claude Code connecte"
    Save-Progress 6
}

function Invoke-Step6 {
    Write-Step "Etape 6/10 : Compte GitHub"

    Write-Manual @"
Vous devez avoir un compte GitHub :

  1. Allez sur : https://github.com
  2. Connectez-vous OU creez un compte si vous n'en avez pas
     - Cliquez sur 'Sign up'
     - Suivez les etapes de creation
"@

    Start-Process "https://github.com"
    Wait-ForUser "Appuyez sur Entree une fois connecte a GitHub..."
    Write-Success "Compte GitHub pret"
    Save-Progress 7
}

function Invoke-Step7 {
    Write-Step "Etape 7/10 : Configuration de Git et cle SSH"

    Write-SubStep "Configuration de votre identite Git..."
    Write-Host ""
    $gitName = Read-Host "Votre nom complet (pour les commits Git)"
    $gitEmail = Read-Host "Votre email (celui utilise sur GitHub)"

    # Configurer Git
    git config --global user.name "$gitName"
    git config --global user.email "$gitEmail"
    git config --global init.defaultBranch main
    Write-Success "Git configure pour: $gitName <$gitEmail>"

    # Generer cle SSH
    Write-SubStep "Generation de la cle SSH..."

    $sshDir = "$env:USERPROFILE\.ssh"
    $sshKey = "$sshDir\id_ed25519"

    if (Test-Path $sshKey) {
        Write-WarningMsg "Une cle SSH existe deja"
        Write-Info "Utilisation de la cle existante..."
    } else {
        Write-Info "Generation d'une nouvelle cle SSH..."

        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }

        # Generer la cle avec ssh-keygen
        $sshKeygenPath = "$env:ProgramFiles\Git\usr\bin\ssh-keygen.exe"
        if (Test-Path $sshKeygenPath) {
            & $sshKeygenPath -t ed25519 -C "$gitEmail" -f $sshKey -N '""'
        } else {
            ssh-keygen -t ed25519 -C "$gitEmail" -f $sshKey -N '""'
        }

        Write-Success "Cle SSH generee"
    }

    # Afficher la cle publique
    Write-Host ""
    Write-Host "Votre cle SSH publique :" -ForegroundColor Yellow
    Write-Host "========================" -ForegroundColor Yellow
    Get-Content "$sshKey.pub"
    Write-Host ""

    Write-Success "Git et SSH configures"
    Save-Progress 8
}

function Invoke-Step8 {
    Write-Step "Etape 8/10 : Ajout de la cle SSH a GitHub et creation du repository"

    Write-SubStep "Authentification GitHub via GitHub CLI..."
    Write-Host ""
    Write-Host "Une fenetre de navigateur va s'ouvrir pour vous authentifier a GitHub." -ForegroundColor Yellow
    Write-Host "Suivez les instructions pour autoriser l'acces." -ForegroundColor Yellow
    Write-Host ""

    try {
        gh auth login --web --git-protocol ssh
        Write-Success "Authentification GitHub reussie"
    } catch {
        Write-ErrorMsg "Erreur d'authentification. Reessayez manuellement avec: gh auth login"
    }

    # Test SSH
    Write-SubStep "Test de la connexion SSH..."
    $sshTest = ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1
    if ($sshTest -match "successfully authenticated") {
        Write-Success "Connexion SSH a GitHub fonctionnelle !"
    } else {
        Write-Info "Test SSH effectue"
    }

    # Creation du repository
    Write-Manual @"
Vous devez maintenant creer votre repository GitHub :

  1. Allez sur : https://github.com/new
  2. Repository name : mon-app-vibe (ou le nom de votre projet)
  3. Description : (optionnel)
  4. Choisissez 'Private' ou 'Public'
  5. COCHEZ : 'Add a README file'
  6. Cliquez sur 'Create repository'

  IMPORTANT : Une fois cree, restez sur la page du repository !
"@

    Start-Process "https://github.com/new"
    Wait-ForUser "Appuyez sur Entree une fois le repository cree..."
    Write-Success "Repository GitHub cree"
    Save-Progress 9
}

function Invoke-Step9 {
    Write-Step "Etape 9/10 : Cloner le repository en local"

    Write-Host ""
    Write-Host "Recuperons l'URL SSH de votre repository :" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Sur la page de votre repository GitHub" -ForegroundColor Gray
    Write-Host "  2. Cliquez sur le bouton vert 'Code'" -ForegroundColor Gray
    Write-Host "  3. Selectionnez l'onglet 'SSH'" -ForegroundColor Gray
    Write-Host "  4. Copiez l'URL (format: git@github.com:username/repo.git)" -ForegroundColor Gray
    Write-Host ""

    # Boucle pour le clonage avec gestion d'erreur
    while ($true) {
        $script:RepoUrl = Read-Host "Collez l'URL SSH de votre repository"

        if ([string]::IsNullOrWhiteSpace($script:RepoUrl)) {
            Write-WarningMsg "URL vide, veuillez reessayer"
            continue
        }

        # Extraire le nom du repo
        $script:RepoName = [System.IO.Path]::GetFileNameWithoutExtension($script:RepoUrl)

        Write-SubStep "Clonage du repository..."

        # Creer le dossier Documents si necessaire
        $docsPath = "$env:USERPROFILE\Documents"
        if (-not (Test-Path $docsPath)) {
            New-Item -ItemType Directory -Path $docsPath -Force | Out-Null
        }

        $repoPath = "$docsPath\$($script:RepoName)"

        # Supprimer si existe deja
        if (Test-Path $repoPath) {
            Write-WarningMsg "Le dossier existe deja, suppression..."
            Remove-Item $repoPath -Recurse -Force
        }

        try {
            Push-Location $docsPath
            git clone $script:RepoUrl
            Pop-Location

            if (Test-Path $repoPath) {
                Write-Success "Repository clone dans $repoPath"
                break
            } else {
                throw "Le dossier n'a pas ete cree"
            }
        } catch {
            Pop-Location -ErrorAction SilentlyContinue
            Write-ErrorMsg "Erreur lors du clonage: $_"
            Write-Host ""
            Write-Host "Que voulez-vous faire ?" -ForegroundColor Yellow
            Write-Host "  [R] Reessayer avec une nouvelle URL"
            Write-Host "  [S] Passer cette etape"
            Write-Host "  [Q] Quitter le script"
            Write-Host ""

            $choice = Read-Host "Votre choix (R/S/Q)"

            switch ($choice.ToUpper()) {
                "R" { continue }
                "S" {
                    Write-WarningMsg "Etape passee - vous devrez cloner manuellement"
                    break
                }
                "Q" {
                    Save-Progress 9
                    Write-Host "`nProgression sauvegardee. Vous pourrez reprendre plus tard." -ForegroundColor Yellow
                    exit 0
                }
            }

            if ($choice.ToUpper() -eq "S") { break }
        }
    }

    Save-Progress 10
}

function Invoke-Step10 {
    Write-Step "Etape 10/10 : Configuration de Supabase et MCP"

    Write-Manual @"
Vous devez creer un compte Supabase et un projet :

  1. Allez sur : https://supabase.com
  2. Cliquez sur 'Start your project' ou 'Sign In'
  3. Connectez-vous (avec GitHub c'est plus simple)

Une fois connecte :

  4. Cliquez sur 'New Project'
  5. Choisissez une organisation (ou creez-en une)
  6. Remplissez :
     - Project name : le nom de votre projet
     - Database password : cliquez 'Generate' (NOTEZ-LE quelque part !)
     - Region : West EU (Ireland)
  7. Cliquez sur 'Create new project'
  8. Attendez ~2 minutes que le projet soit cree
"@

    Start-Process "https://supabase.com"
    Wait-ForUser "Appuyez sur Entree une fois votre projet Supabase cree..."

    Write-Manual @"
Maintenant, recuperez la commande MCP depuis Supabase :

  1. Dans votre projet Supabase, cliquez sur 'Connect' (en haut a droite)
  2. Cliquez sur l'onglet 'MCP'
  3. Selectionnez 'Claude Code'
  4. COPIEZ la commande affichee
     (elle ressemble a : claude mcp add ...)
"@

    Wait-ForUser "Appuyez sur Entree quand vous avez copie la commande MCP..."

    # Recuperer le nom du repo si pas deja fait
    if ([string]::IsNullOrWhiteSpace($script:RepoName)) {
        $script:RepoName = Read-Host "Quel est le nom de votre repository (dossier dans Documents)"
    }

    $repoPath = "$env:USERPROFILE\Documents\$($script:RepoName)"

    # Boucle pour la commande MCP
    while ($true) {
        Write-Host ""
        $mcpCommand = Read-Host "Collez la commande MCP ici"

        if ([string]::IsNullOrWhiteSpace($mcpCommand)) {
            Write-WarningMsg "Commande vide, veuillez reessayer"
            continue
        }

        Write-SubStep "Execution de la commande MCP..."

        try {
            Push-Location $repoPath
            Invoke-Expression $mcpCommand
            Pop-Location
            Write-Success "MCP Supabase configure"
            break
        } catch {
            Pop-Location -ErrorAction SilentlyContinue
            Write-ErrorMsg "Erreur lors de l'execution: $_"
            Write-Host ""
            Write-Host "Que voulez-vous faire ?" -ForegroundColor Yellow
            Write-Host "  [R] Reessayer avec une nouvelle commande"
            Write-Host "  [S] Passer cette etape"
            Write-Host "  [Q] Quitter le script"
            Write-Host ""

            $choice = Read-Host "Votre choix (R/S/Q)"

            switch ($choice.ToUpper()) {
                "R" { continue }
                "S" {
                    Write-WarningMsg "Etape passee - vous devrez configurer MCP manuellement"
                    break
                }
                "Q" {
                    Save-Progress 10
                    Write-Host "`nProgression sauvegardee. Vous pourrez reprendre plus tard." -ForegroundColor Yellow
                    exit 0
                }
            }

            if ($choice.ToUpper() -eq "S") { break }
        }
    }

    Write-Manual @"
Derniere verification - Lancez Claude Code et verifiez MCP :

  1. Ouvrez Git Bash
  2. Allez dans votre projet :
     cd ~/Documents/$($script:RepoName)

  3. Lancez Claude Code :
     claude

  4. Tapez la commande :
     /mcp

  5. Verifiez que 'supabase' apparait dans la liste des serveurs MCP
"@

    Wait-ForUser "Appuyez sur Entree une fois MCP verifie..."
    Write-Success "Supabase connecte a Claude Code"

    # Nettoyer le fichier de progression
    if (Test-Path $PROGRESS_FILE) {
        Remove-Item $PROGRESS_FILE -Force
    }
}

function Show-Completion {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  INSTALLATION TERMINEE AVEC SUCCES !" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resume de ce qui a ete installe et configure :" -ForegroundColor White
    Write-Host "  [OK] Git for Windows (avec Git Bash)" -ForegroundColor Green
    Write-Host "  [OK] Node.js" -ForegroundColor Green
    Write-Host "  [OK] GitHub CLI" -ForegroundColor Green
    Write-Host "  [OK] Git (avec votre identite)" -ForegroundColor Green
    Write-Host "  [OK] Cle SSH (ajoutee a GitHub)" -ForegroundColor Green
    Write-Host "  [OK] Claude Code (connecte a votre compte)" -ForegroundColor Green
    Write-Host "  [OK] Repository GitHub (clone en local)" -ForegroundColor Green
    Write-Host "  [OK] Supabase (connecte via MCP)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pour commencer a coder :" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Ouvrez Git Bash" -ForegroundColor White
    Write-Host "  2. Allez dans votre projet :" -ForegroundColor White

    if (-not [string]::IsNullOrWhiteSpace($script:RepoName)) {
        Write-Host "     cd ~/Documents/$($script:RepoName)" -ForegroundColor Cyan
    } else {
        Write-Host "     cd ~/Documents/votre-projet" -ForegroundColor Cyan
    }

    Write-Host "  3. Lancez Claude Code :" -ForegroundColor White
    Write-Host "     claude" -ForegroundColor Cyan
    Write-Host "  4. Decrivez ce que vous voulez construire !" -ForegroundColor White
    Write-Host ""
    Write-Host "Bon vibecoding ! " -ForegroundColor Magenta
    Write-Host ""
}

# ============================================
# MAIN
# ============================================

# Afficher l'aide si demande
if ($Help) {
    Show-Help
    exit 0
}

# Verification admin
if (-not (Test-Administrator)) {
    Show-Banner
    Write-ErrorMsg "Ce script doit etre execute en tant qu'Administrateur !"
    Write-Info "Clic droit sur PowerShell > Executer en tant qu'administrateur"
    exit 1
}

# Reset si demande
if ($Reset) {
    Reset-Progress
    $Step = 1
}

# Determiner l'etape de depart
$startStep = $Step
if ($startStep -eq 0) {
    $startStep = Show-Menu
}

# Valider l'etape
if ($startStep -lt 1 -or $startStep -gt 10) {
    $startStep = 1
}

Write-Host ""
Write-Host "Demarrage a l'etape $startStep..." -ForegroundColor Cyan
Write-Host ""

# Executer les etapes
$steps = @(
    { Invoke-Step1 },
    { Invoke-Step2 },
    { Invoke-Step3 },
    { Invoke-Step4 },
    { Invoke-Step5 },
    { Invoke-Step6 },
    { Invoke-Step7 },
    { Invoke-Step8 },
    { Invoke-Step9 },
    { Invoke-Step10 }
)

for ($i = $startStep - 1; $i -lt $steps.Count; $i++) {
    try {
        & $steps[$i]
    } catch {
        Write-ErrorMsg "Erreur a l'etape $($i + 1): $_"
        Save-Progress ($i + 1)

        Write-Host ""
        Write-Host "Que voulez-vous faire ?" -ForegroundColor Yellow
        Write-Host "  [R] Reessayer cette etape"
        Write-Host "  [S] Passer a l'etape suivante"
        Write-Host "  [Q] Quitter le script"
        Write-Host ""

        $choice = Read-Host "Votre choix (R/S/Q)"

        switch ($choice.ToUpper()) {
            "R" {
                $i--
                continue
            }
            "S" { continue }
            "Q" {
                Write-Host "`nProgression sauvegardee. Vous pourrez reprendre plus tard." -ForegroundColor Yellow
                exit 0
            }
        }
    }
}

# Afficher le message de fin
Show-Completion
