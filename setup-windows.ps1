#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de setup automatique pour la formation Vibecoding (Windows)

.DESCRIPTION
    Ce script installe et configure tout l'environnement necessaire.
    Il guide l'utilisateur etape par etape, avec des pauses pour les actions manuelles.

    Fonctionnalites v3.0 :
    - Menu pour choisir l'etape de depart
    - Sauvegarde de la progression
    - Gestion des erreurs avec retry/skip/quit
    - Possibilite de reprendre ou de repartir de zero

.PARAMETER Step
    Numero de l'etape a laquelle commencer (1-10)

.PARAMETER Reset
    Remet la progression a zero et recommence depuis le debut

.EXAMPLE
    .\setup-windows.ps1
    .\setup-windows.ps1 -Step 5
    .\setup-windows.ps1 -Reset

.NOTES
    Auteur: Formation Vibecoding
    Version: 3.1
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
$SCRIPT_VERSION = "3.1"

# Variables globales pour le repo
$script:RepoUrl = ""
$script:RepoName = ""

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

           Setup Automatique Windows - v$SCRIPT_VERSION

"@ -ForegroundColor Magenta
}

function Show-Help {
    Show-Banner
    Write-Host "UTILISATION:" -ForegroundColor Yellow
    Write-Host "  .\setup-windows.ps1              Lancer avec menu interactif"
    Write-Host "  .\setup-windows.ps1 -Step 5      Demarrer a l'etape 5"
    Write-Host "  .\setup-windows.ps1 -Reset       Repartir de zero"
    Write-Host "  .\setup-windows.ps1 -Help        Afficher cette aide"
    Write-Host ""
    Write-Host "ETAPES:" -ForegroundColor Yellow
    Write-Host "  1. Compte Anthropic et abonnement Max"
    Write-Host "  2. Installation WSL (Windows Subsystem for Linux)"
    Write-Host "  3. Installation outils (Node.js, Git, GitHub CLI, Claude Code)"
    Write-Host "  4. Connexion a Claude Code"
    Write-Host "  5. Compte GitHub"
    Write-Host "  6. Configuration Git et cle SSH"
    Write-Host "  7. Ajout cle SSH a GitHub + creation repository"
    Write-Host "  8. Cloner le repository"
    Write-Host "  9. Configuration Supabase"
    Write-Host "  10. Connexion MCP Supabase"
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
    Write-Host "Certaines etapes necessitent des actions manuelles de votre part." -ForegroundColor Yellow
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
        "Installation WSL",
        "Installation outils (Node.js, Git, GitHub CLI, Claude Code)",
        "Connexion a Claude Code",
        "Compte GitHub",
        "Configuration Git et cle SSH",
        "Ajout cle SSH a GitHub + creation repository",
        "Cloner le repository",
        "Configuration Supabase",
        "Connexion MCP Supabase"
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
        # Restaurer les variables sauvegardees
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
  3. Prenez l'abonnement MAX a 90 euros/mois
     (utilisez les cartes fournies pour la formation)
"@

    Start-Process "https://claude.ai"
    Wait-ForUser "Appuyez sur Entree une fois votre compte cree et l'abonnement Max active..."
    Write-Success "Compte Anthropic configure"
    Save-Progress 2
}

function Invoke-Step2 {
    Write-Step "Etape 2/10 : Installation de WSL (Windows Subsystem for Linux)"

    # Verifier si WSL est installe
    $wslInstalled = $false
    try {
        $wslStatus = wsl --status 2>&1
        if ($LASTEXITCODE -eq 0) {
            $wslInstalled = $true
            Write-Success "WSL est deja installe"
        }
    } catch {
        $wslInstalled = $false
    }

    if (-not $wslInstalled) {
        Write-SubStep "Installation de WSL et Ubuntu en cours..."
        Write-Info "Cela peut prendre plusieurs minutes..."

        Write-Manual @"
L'installation de WSL et Ubuntu va demarrer.
Une fenetre Ubuntu va s'ouvrir automatiquement.

  1. Attendez l'initialisation (peut prendre 2-3 minutes)
  2. Creez un nom d'utilisateur (en minuscules, sans espaces)
  3. Creez un mot de passe (vous ne le verrez pas s'afficher, c'est normal)
  4. Une fois le prompt vert affiche (ex: user@PC:~$), tapez : exit
  5. Revenez ici et appuyez sur Entree
"@

        Invoke-WithRetry -Description "Installation WSL + Ubuntu" -Action {
            wsl --install -d Ubuntu
            if ($LASTEXITCODE -ne 0) { throw "Echec de l'installation WSL/Ubuntu" }
        }

        Wait-ForUser "Appuyez sur Entree une fois Ubuntu configure et ferme..."
        Write-Success "WSL et Ubuntu installes"
    }

    # Verifier si Ubuntu est installe ET initialise
    Write-SubStep "Verification de la distribution Ubuntu..."

    $ubuntuReady = $false
    try {
        # Tester si on peut executer une commande dans WSL
        $testResult = wsl -d Ubuntu -- echo "ok" 2>&1
        if ($LASTEXITCODE -eq 0 -and $testResult -match "ok") {
            $ubuntuReady = $true
            Write-Success "Ubuntu est disponible et configure"
        }
    } catch {
        $ubuntuReady = $false
    }

    if (-not $ubuntuReady) {
        # Verifier si Ubuntu est dans la liste
        $distros = wsl -l -q 2>&1

        if ($distros -notmatch "Ubuntu") {
            Write-WarningMsg "Ubuntu n'est pas installe. Installation..."

            Write-Manual @"
L'installation d'Ubuntu va demarrer.
Une fenetre Ubuntu va s'ouvrir automatiquement.

  1. Attendez l'initialisation (peut prendre 2-3 minutes)
  2. Creez un nom d'utilisateur (en minuscules, sans espaces)
  3. Creez un mot de passe (vous ne le verrez pas s'afficher, c'est normal)
  4. Une fois le prompt vert affiche (ex: user@PC:~$), tapez : exit
  5. Revenez ici et appuyez sur Entree
"@

            Invoke-WithRetry -Description "Installation Ubuntu" -Action {
                wsl --install -d Ubuntu
                if ($LASTEXITCODE -ne 0) { throw "Echec de l'installation Ubuntu" }
            }

            Wait-ForUser "Appuyez sur Entree une fois Ubuntu configure et ferme..."
        } else {
            # Ubuntu est installe mais pas initialise
            Write-Manual @"
Ubuntu doit etre initialise. Suivez ces etapes :

  1. Ouvrez 'Ubuntu' depuis le menu Demarrer Windows
     (tapez 'Ubuntu' dans la barre de recherche)
  2. Attendez l'initialisation (peut prendre 1-2 minutes)
  3. Creez un nom d'utilisateur (en minuscules, sans espaces)
  4. Creez un mot de passe (vous ne le verrez pas s'afficher, c'est normal)
  5. Une fois le prompt vert affiche (ex: user@PC:~$), tapez : exit
  6. Fermez la fenetre Ubuntu
"@
            Wait-ForUser "Appuyez sur Entree une fois Ubuntu configure..."
        }

        # Re-verifier apres l'action manuelle
        try {
            $testResult = wsl -d Ubuntu -- echo "ok" 2>&1
            if ($LASTEXITCODE -eq 0 -and $testResult -match "ok") {
                Write-Success "Ubuntu est maintenant configure"
            } else {
                Write-WarningMsg "Ubuntu semble ne pas etre pret, mais on continue..."
            }
        } catch {
            Write-WarningMsg "Impossible de verifier Ubuntu, mais on continue..."
        }
    }

    Save-Progress 3
}

function Invoke-Step3 {
    Write-Step "Etape 3/10 : Installation des outils (Node.js, Git, GitHub CLI, Claude Code)"

    Write-SubStep "Installation en cours dans WSL..."

    $wslScript = @'
#!/bin/bash
set -e

echo ">> Mise a jour des paquets..."
sudo apt update && sudo apt upgrade -y

echo ""
echo ">> Installation de Node.js LTS..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
fi
echo "[OK] Node.js $(node --version)"

echo ""
echo ">> Installation de Git..."
sudo apt install -y git
echo "[OK] Git $(git --version)"

echo ""
echo ">> Installation de GitHub CLI..."
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh -y
fi
echo "[OK] GitHub CLI $(gh --version | head -1)"

echo ""
echo ">> Installation de Claude Code..."
if ! command -v claude &> /dev/null; then
    sudo npm install -g @anthropic-ai/claude-code
fi
echo "[OK] Claude Code installe"

echo ""
echo "=== Tous les outils sont installes ==="
'@

    $success = Invoke-WithRetry -Description "Installation outils WSL" -Action {
        $result = $wslScript | wsl bash 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Erreur dans le script WSL: $result" }
        Write-Host $result
    }

    if ($success) {
        Write-Success "Outils installes dans WSL"
    }
    Save-Progress 4
}

function Invoke-Step4 {
    Write-Step "Etape 4/10 : Connexion a Claude Code"

    Write-Manual @"
Vous devez maintenant connecter Claude Code a votre compte Anthropic :

  1. Dans une fenetre Ubuntu (ou WSL), tapez : claude
  2. Choisissez 'Claude Max (subscription)' (PAS 'API Key')
  3. Un navigateur va s'ouvrir, connectez-vous avec votre compte Anthropic
  4. Quand Claude demande les 'settings', gardez les options par defaut
  5. S'il demande de 'trust the folder', repondez 'yes'
  6. Posez une question simple pour verifier que ca marche
  7. Tapez /exit pour quitter Claude Code
"@

    Wait-ForUser "Appuyez sur Entree une fois connecte a Claude Code..."
    Write-Success "Claude Code connecte"
    Save-Progress 5
}

function Invoke-Step5 {
    Write-Step "Etape 5/10 : Compte GitHub"

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
    Save-Progress 6
}

function Invoke-Step6 {
    Write-Step "Etape 6/10 : Configuration de Git et cle SSH"

    Write-SubStep "Configuration de votre identite Git..."
    Write-Host ""
    $gitName = Read-Host "Votre nom complet (pour les commits Git)"
    $gitEmail = Read-Host "Votre email (celui utilise sur GitHub)"

    $gitConfigScript = @"
#!/bin/bash
git config --global user.name "$gitName"
git config --global user.email "$gitEmail"
git config --global init.defaultBranch main
echo "[OK] Git configure pour: $gitName <$gitEmail>"
"@

    Invoke-WithRetry -Description "Configuration Git" -Action {
        $gitConfigScript | wsl bash
    }

    Write-SubStep "Generation de la cle SSH..."

    $sshScript = @"
#!/bin/bash

SSH_KEY=~/.ssh/id_ed25519

if [ -f "\`$SSH_KEY" ]; then
    echo "[!] Une cle SSH existe deja"
    echo "    Utilisation de la cle existante..."
else
    echo ">> Generation d'une nouvelle cle SSH..."
    mkdir -p ~/.ssh
    ssh-keygen -t ed25519 -C "$gitEmail" -f ~/.ssh/id_ed25519 -N "" -q
    chmod 600 ~/.ssh/id_ed25519
    chmod 644 ~/.ssh/id_ed25519.pub
    echo "[OK] Cle SSH generee"
fi

# Demarrer ssh-agent et ajouter la cle
eval "\`$(ssh-agent -s)" > /dev/null
ssh-add ~/.ssh/id_ed25519 2>/dev/null

echo ""
echo "Votre cle SSH publique :"
echo "========================"
cat ~/.ssh/id_ed25519.pub
echo ""
"@

    Invoke-WithRetry -Description "Generation cle SSH" -Action {
        $sshScript | wsl bash
    }

    Write-Success "Git et SSH configures"
    Save-Progress 7
}

function Invoke-Step7 {
    Write-Step "Etape 7/10 : Ajout de la cle SSH a GitHub et creation du repository"

    Write-SubStep "Ajout de la cle SSH via GitHub CLI..."
    Write-Host ""
    Write-Host "Une fenetre de navigateur va s'ouvrir pour vous authentifier a GitHub." -ForegroundColor Yellow
    Write-Host "Suivez les instructions pour autoriser l'acces." -ForegroundColor Yellow
    Write-Host ""

    $ghAuthScript = @'
#!/bin/bash
echo ">> Authentification GitHub..."
gh auth login --web --git-protocol ssh

if gh auth status &>/dev/null; then
    echo ""
    echo "[OK] Authentification GitHub reussie !"
    echo "[OK] Cle SSH ajoutee a votre compte GitHub"
else
    echo "[X] Erreur d'authentification"
    exit 1
fi
'@

    Invoke-WithRetry -Description "Authentification GitHub" -Action {
        $ghAuthScript | wsl bash
        if ($LASTEXITCODE -ne 0) { throw "Echec authentification GitHub" }
    }

    # Test SSH
    Write-SubStep "Test de la connexion SSH..."
    $testScript = @'
#!/bin/bash
ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 || true
'@
    $testResult = $testScript | wsl bash

    if ($testResult -match "successfully authenticated") {
        Write-Success "Connexion SSH a GitHub fonctionnelle !"
    } else {
        Write-Info "Test SSH effectue (le message d'erreur est normal si c'est la premiere connexion)"
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
    Save-Progress 8
}

function Invoke-Step8 {
    Write-Step "Etape 8/10 : Cloner le repository en local"

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

        $cloneScript = @"
#!/bin/bash
cd ~
mkdir -p Documents
cd Documents

REPO_NAME="$($script:RepoName)"

if [ -d "`$REPO_NAME" ]; then
    echo "[!] Le dossier `$REPO_NAME existe deja"
    echo "    Suppression et re-clonage..."
    rm -rf "`$REPO_NAME"
fi

echo ">> Clonage de $($script:RepoUrl)..."
git clone "$($script:RepoUrl)"
echo "[OK] Repository clone dans ~/Documents/`$REPO_NAME"
"@

        try {
            $result = $cloneScript | wsl bash 2>&1
            Write-Host $result

            if ($LASTEXITCODE -eq 0) {
                Write-Success "Repository clone"
                break
            } else {
                throw "Erreur de clonage"
            }
        } catch {
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
                    Save-Progress 8
                    Write-Host "`nProgression sauvegardee. Vous pourrez reprendre plus tard." -ForegroundColor Yellow
                    exit 0
                }
            }

            if ($choice.ToUpper() -eq "S") { break }
        }
    }

    Save-Progress 9
}

function Invoke-Step9 {
    Write-Step "Etape 9/10 : Configuration de Supabase"

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
    Write-Success "Projet Supabase cree"
    Save-Progress 10
}

function Invoke-Step10 {
    Write-Step "Etape 10/10 : Connexion de Supabase a Claude Code (MCP)"

    Write-Manual @"
Vous devez maintenant recuperer la commande MCP depuis Supabase :

  1. Dans votre projet Supabase, cliquez sur 'Connect' (en haut a droite)
  2. Cliquez sur l'onglet 'MCP'
  3. Selectionnez 'Claude Code'
  4. COPIEZ la commande affichee
     (elle ressemble a : claude mcp add --scope project ...)
"@

    Wait-ForUser "Appuyez sur Entree quand vous avez copie la commande MCP..."

    # Recuperer le nom du repo si pas deja fait
    if ([string]::IsNullOrWhiteSpace($script:RepoName)) {
        $script:RepoName = Read-Host "Quel est le nom de votre repository (dossier dans ~/Documents)"
    }

    # Boucle pour la commande MCP avec gestion d'erreur
    while ($true) {
        Write-Host ""
        $mcpCommand = Read-Host "Collez la commande MCP ici"

        if ([string]::IsNullOrWhiteSpace($mcpCommand)) {
            Write-WarningMsg "Commande vide, veuillez reessayer"
            continue
        }

        Write-SubStep "Execution de la commande MCP dans votre projet..."

        $mcpScript = @"
#!/bin/bash
cd ~/Documents/$($script:RepoName)
$mcpCommand
echo ""
echo "[OK] MCP Supabase configure"
"@

        try {
            $result = $mcpScript | wsl bash 2>&1
            Write-Host $result

            if ($LASTEXITCODE -eq 0) {
                break
            } else {
                throw "Erreur MCP"
            }
        } catch {
            Write-ErrorMsg "Erreur lors de l'execution de la commande MCP: $_"
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

  1. Dans Ubuntu, allez dans votre projet :
     cd ~/Documents/$($script:RepoName)

  2. Lancez Claude Code :
     claude

  3. Tapez la commande :
     /mcp

  4. Appuyez sur Entree puis ACCEPTEZ la connexion
     quand Claude demande d'autoriser le serveur MCP Supabase

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
    Write-Host "  [OK] WSL avec Ubuntu" -ForegroundColor Green
    Write-Host "  [OK] Node.js" -ForegroundColor Green
    Write-Host "  [OK] Git (avec votre identite)" -ForegroundColor Green
    Write-Host "  [OK] GitHub CLI" -ForegroundColor Green
    Write-Host "  [OK] Cle SSH (ajoutee a GitHub)" -ForegroundColor Green
    Write-Host "  [OK] Claude Code (connecte a votre compte)" -ForegroundColor Green
    Write-Host "  [OK] Repository GitHub (clone en local)" -ForegroundColor Green
    Write-Host "  [OK] Supabase (connecte via MCP)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pour commencer a coder :" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Ouvrez Ubuntu" -ForegroundColor White
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
