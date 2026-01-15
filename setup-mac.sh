#!/bin/bash

#===============================================================================
# Script de setup automatique pour la formation Vibecoding (macOS)
#
# Ce script installe et configure tout l'environnement necessaire.
# Il guide l'utilisateur etape par etape, avec des pauses pour les actions manuelles.
#
# Usage : chmod +x setup-mac.sh && ./setup-mac.sh
#         ./setup-mac.sh --step 5    # Commencer à l'étape 5
#         ./setup-mac.sh --reset     # Recommencer depuis le début
#
# Version: 3.0
#===============================================================================

set -E  # Inherit ERR trap in functions

# Fichier de progression
PROGRESS_FILE="$HOME/.vibecoding_setup_progress"

# Variables globales (seront définies au fur et à mesure)
GIT_NAME=""
GIT_EMAIL=""
REPO_URL=""
REPO_NAME=""
MCP_COMMAND=""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m'

# Fonctions d'affichage
step() {
    echo ""
    echo -e "${CYAN}========================================"
    echo -e "  $1"
    echo -e "========================================${NC}"
}

substep() { echo -e "\n${WHITE}>> $1${NC}"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[X]${NC} $1"; }
info() { echo -e "${GRAY}    $1${NC}"; }

manual_action() {
    echo ""
    echo -e "${MAGENTA}--------------------------------------------"
    echo -e "  ACTION MANUELLE REQUISE"
    echo -e "--------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo ""
}

wait_for_user() {
    local msg="${1:-Appuyez sur Entree une fois termine...}"
    echo ""
    read -p "$msg"
}

# Sauvegarde de la progression
save_progress() {
    local step=$1
    echo "CURRENT_STEP=$step" > "$PROGRESS_FILE"
    [ -n "$GIT_NAME" ] && echo "GIT_NAME=\"$GIT_NAME\"" >> "$PROGRESS_FILE"
    [ -n "$GIT_EMAIL" ] && echo "GIT_EMAIL=\"$GIT_EMAIL\"" >> "$PROGRESS_FILE"
    [ -n "$REPO_URL" ] && echo "REPO_URL=\"$REPO_URL\"" >> "$PROGRESS_FILE"
    [ -n "$REPO_NAME" ] && echo "REPO_NAME=\"$REPO_NAME\"" >> "$PROGRESS_FILE"
}

# Chargement de la progression
load_progress() {
    if [ -f "$PROGRESS_FILE" ]; then
        source "$PROGRESS_FILE"
        return 0
    fi
    return 1
}

# Afficher le menu de sélection d'étape
show_menu() {
    echo ""
    echo -e "${CYAN}========================================"
    echo -e "  MENU DE DEMARRAGE"
    echo -e "========================================${NC}"
    echo ""
    echo "  [0]  Commencer depuis le debut"
    echo ""
    echo "  [1]  Etape 1  : Compte Anthropic + abonnement"
    echo "  [2]  Etape 2  : Installer Homebrew"
    echo "  [3]  Etape 3  : Installer les outils (Node, Git, etc.)"
    echo "  [4]  Etape 4  : Connexion a Claude Code"
    echo "  [5]  Etape 5  : Compte GitHub"
    echo "  [6]  Etape 6  : Configuration Git + cle SSH"
    echo "  [7]  Etape 7  : Ajouter SSH a GitHub + creer repo"
    echo "  [8]  Etape 8  : Cloner le repository"
    echo "  [9]  Etape 9  : Creer projet Supabase"
    echo "  [10] Etape 10 : Connecter Supabase (MCP)"
    echo ""

    if [ -f "$PROGRESS_FILE" ]; then
        source "$PROGRESS_FILE"
        echo -e "${YELLOW}  [R]  Reprendre a l'etape $CURRENT_STEP (derniere progression)${NC}"
        echo ""
    fi

    echo "  [Q]  Quitter"
    echo ""
    read -p "Votre choix : " MENU_CHOICE

    case $MENU_CHOICE in
        [0-9]|10) START_STEP=$MENU_CHOICE ;;
        [Rr])
            if [ -f "$PROGRESS_FILE" ]; then
                source "$PROGRESS_FILE"
                START_STEP=$CURRENT_STEP
            else
                START_STEP=1
            fi
            ;;
        [Qq]) exit 0 ;;
        *) START_STEP=1 ;;
    esac
}

# Fonction pour réessayer une commande
retry_command() {
    local cmd="$1"
    local description="$2"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if eval "$cmd"; then
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo ""
                error "La commande a echoue."
                echo ""
                echo "Options :"
                echo "  [R] Reessayer"
                echo "  [S] Passer cette etape"
                echo "  [Q] Quitter le script"
                echo ""
                read -p "Votre choix (R/S/Q) : " RETRY_CHOICE
                case $RETRY_CHOICE in
                    [Ss])
                        warn "Etape passee. Vous devrez peut-etre la faire manuellement."
                        return 1
                        ;;
                    [Qq])
                        echo "Script interrompu. Vous pourrez reprendre plus tard."
                        exit 0
                        ;;
                    *)
                        echo "Nouvelle tentative..."
                        ;;
                esac
            fi
        fi
    done

    error "Echec apres $max_retries tentatives."
    echo ""
    echo "Options :"
    echo "  [S] Passer cette etape"
    echo "  [Q] Quitter le script"
    echo ""
    read -p "Votre choix (S/Q) : " FINAL_CHOICE
    case $FINAL_CHOICE in
        [Qq]) exit 0 ;;
        *) return 1 ;;
    esac
}

# Fonction pour demander une entrée avec validation
ask_with_retry() {
    local prompt="$1"
    local var_name="$2"
    local validation_cmd="$3"  # Optionnel : commande pour valider l'entrée

    while true; do
        read -p "$prompt" INPUT_VALUE

        if [ -z "$INPUT_VALUE" ]; then
            warn "La valeur ne peut pas etre vide. Reessayez."
            continue
        fi

        if [ -n "$validation_cmd" ]; then
            if eval "$validation_cmd \"$INPUT_VALUE\""; then
                eval "$var_name=\"$INPUT_VALUE\""
                return 0
            else
                error "Valeur invalide. Reessayez."
                continue
            fi
        else
            eval "$var_name=\"$INPUT_VALUE\""
            return 0
        fi
    done
}

#===============================================================================
# ETAPES
#===============================================================================

etape_1() {
    step "Etape 1/10 : Compte Anthropic et abonnement"
    save_progress 1

    manual_action "Vous devez creer un compte Anthropic et prendre l'abonnement Max :

  1. Allez sur : https://claude.ai
  2. Creez un compte (ou connectez-vous)
  3. Prenez l'abonnement MAX a 90 euros/mois
     (utilisez les cartes fournies pour la formation)"

    open "https://claude.ai" 2>/dev/null || echo "Ouvrez manuellement : https://claude.ai"

    wait_for_user "Appuyez sur Entree une fois votre compte cree et l'abonnement Max active..."
    success "Compte Anthropic configure"
}

etape_2() {
    step "Etape 2/10 : Installation de Homebrew"
    save_progress 2

    if command -v brew &> /dev/null; then
        success "Homebrew est deja installe"
        substep "Mise a jour de Homebrew..."
        brew update --quiet || warn "Mise a jour ignoree"
    else
        warn "Homebrew n'est pas installe. Installation en cours..."
        info "Cela peut prendre quelques minutes..."
        info "Vous devrez peut-etre entrer votre mot de passe Mac."

        if retry_command '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' "Installation Homebrew"; then
            # Ajouter Homebrew au PATH pour les Mac Apple Silicon
            if [[ $(uname -m) == "arm64" ]]; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
            success "Homebrew installe"
        else
            error "Installation de Homebrew echouee"
            echo "Vous pouvez l'installer manuellement : https://brew.sh"
        fi
    fi

    # S'assurer que brew est dans le PATH
    if [[ $(uname -m) == "arm64" ]] && [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
}

etape_3() {
    step "Etape 3/10 : Installation des outils (Node.js, Git, GitHub CLI, Claude Code)"
    save_progress 3

    substep "Installation via Homebrew..."

    # Node.js
    if command -v node &> /dev/null; then
        success "Node.js deja installe ($(node --version))"
    else
        info "Installation de Node.js..."
        retry_command "brew install node" "Installation Node.js" && success "Node.js installe ($(node --version))"
    fi

    # Git
    if command -v git &> /dev/null; then
        success "Git deja installe ($(git --version | cut -d' ' -f3))"
    else
        info "Installation de Git..."
        retry_command "brew install git" "Installation Git" && success "Git installe"
    fi

    # GitHub CLI
    if command -v gh &> /dev/null; then
        success "GitHub CLI deja installe"
    else
        info "Installation de GitHub CLI..."
        retry_command "brew install gh" "Installation GitHub CLI" && success "GitHub CLI installe"
    fi

    # Claude Code
    if command -v claude &> /dev/null; then
        success "Claude Code deja installe"
    else
        info "Installation de Claude Code..."
        retry_command "npm install -g @anthropic-ai/claude-code" "Installation Claude Code" && success "Claude Code installe"
    fi
}

etape_4() {
    step "Etape 4/10 : Connexion a Claude Code"
    save_progress 4

    manual_action "Vous devez maintenant connecter Claude Code a votre compte Anthropic :

  1. Ouvrez un NOUVEAU Terminal (important pour que les chemins soient a jour)
  2. Tapez : claude
  3. Choisissez 'Claude Max (subscription)' (PAS 'API Key')
  4. Un navigateur va s'ouvrir, connectez-vous avec votre compte Anthropic
  5. Quand Claude demande les 'settings', gardez les options par defaut
  6. S'il demande de 'trust the folder', repondez 'yes'
  7. Posez une question simple pour verifier que ca marche
  8. Tapez /exit pour quitter Claude Code"

    wait_for_user "Appuyez sur Entree une fois connecte a Claude Code..."
    success "Claude Code connecte"
}

etape_5() {
    step "Etape 5/10 : Compte GitHub"
    save_progress 5

    manual_action "Vous devez avoir un compte GitHub :

  1. Allez sur : https://github.com
  2. Connectez-vous OU creez un compte si vous n'en avez pas
     - Cliquez sur 'Sign up'
     - Suivez les etapes de creation"

    open "https://github.com" 2>/dev/null || echo "Ouvrez manuellement : https://github.com"

    wait_for_user "Appuyez sur Entree une fois connecte a GitHub..."
    success "Compte GitHub pret"
}

etape_6() {
    step "Etape 6/10 : Configuration de Git et cle SSH"
    save_progress 6

    substep "Configuration de votre identite Git..."

    # Charger les valeurs sauvegardées si disponibles
    load_progress

    # Verifier si Git est deja configure
    CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$CURRENT_NAME" && -n "$CURRENT_EMAIL" ]]; then
        success "Git deja configure pour : $CURRENT_NAME <$CURRENT_EMAIL>"
        read -p "Voulez-vous modifier cette configuration ? (o/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Oo]$ ]]; then
            CURRENT_NAME=""
            CURRENT_EMAIL=""
        else
            GIT_NAME="$CURRENT_NAME"
            GIT_EMAIL="$CURRENT_EMAIL"
        fi
    fi

    if [[ -z "$GIT_NAME" ]]; then
        echo ""
        read -p "Votre nom complet (pour les commits Git) : " GIT_NAME
        read -p "Votre email (celui utilise sur GitHub) : " GIT_EMAIL

        git config --global user.name "$GIT_NAME"
        git config --global user.email "$GIT_EMAIL"
        git config --global init.defaultBranch main

        success "Git configure pour : $GIT_NAME <$GIT_EMAIL>"
    fi

    # Sauvegarder pour les étapes suivantes
    save_progress 6

    substep "Generation de la cle SSH..."

    SSH_KEY="$HOME/.ssh/id_ed25519"

    if [[ -f "$SSH_KEY" ]]; then
        warn "Une cle SSH existe deja"
        info "Utilisation de la cle existante..."
    else
        info "Generation d'une nouvelle cle SSH..."
        mkdir -p ~/.ssh
        ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" -q
        chmod 600 "$SSH_KEY"
        chmod 644 "${SSH_KEY}.pub"
        success "Cle SSH generee"
    fi

    # Configurer ssh-agent pour macOS
    if [[ ! -f ~/.ssh/config ]] || ! grep -q "github.com" ~/.ssh/config 2>/dev/null; then
        cat >> ~/.ssh/config << 'SSHCONFIG'

Host github.com
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519
SSHCONFIG
    fi

    # Demarrer ssh-agent et ajouter la cle
    eval "$(ssh-agent -s)" > /dev/null 2>&1
    ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || ssh-add "$SSH_KEY" 2>/dev/null || true

    echo ""
    echo "Votre cle SSH publique :"
    echo "========================"
    cat "${SSH_KEY}.pub"
    echo ""

    success "Git et SSH configures"
}

etape_7() {
    step "Etape 7/10 : Ajout de la cle SSH a GitHub et creation du repository"
    save_progress 7

    substep "Ajout de la cle SSH via GitHub CLI..."
    echo ""
    echo -e "${YELLOW}Une fenetre de navigateur va s'ouvrir pour vous authentifier a GitHub.${NC}"
    echo -e "${YELLOW}Suivez les instructions pour autoriser l'acces.${NC}"
    echo ""

    # Authentification GitHub
    if gh auth status &>/dev/null; then
        success "Deja authentifie a GitHub"
    else
        if retry_command "gh auth login --web --git-protocol ssh" "Authentification GitHub"; then
            success "Authentification GitHub reussie !"
        else
            error "Authentification GitHub echouee"
            manual_action "Vous pouvez ajouter votre cle SSH manuellement :
  1. Copiez votre cle : cat ~/.ssh/id_ed25519.pub | pbcopy
  2. Allez sur : https://github.com/settings/ssh/new
  3. Collez la cle et sauvegardez"
            wait_for_user "Appuyez sur Entree une fois la cle ajoutee..."
        fi
    fi

    # Test SSH
    substep "Test de la connexion SSH..."
    SSH_TEST=$(ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 || true)

    if echo "$SSH_TEST" | grep -q "successfully authenticated"; then
        success "Connexion SSH a GitHub fonctionnelle !"
    else
        info "Test SSH effectue (le message d'erreur est normal si c'est la premiere connexion)"
    fi

    # Creation du repository
    manual_action "Vous devez maintenant creer votre repository GitHub :

  1. Allez sur : https://github.com/new
  2. Repository name : mon-app-vibe (ou le nom de votre projet)
  3. Description : (optionnel)
  4. Choisissez 'Private' ou 'Public'
  5. COCHEZ : 'Add a README file'
  6. Cliquez sur 'Create repository'

  IMPORTANT : Une fois cree, restez sur la page du repository !"

    open "https://github.com/new" 2>/dev/null || echo "Ouvrez manuellement : https://github.com/new"

    wait_for_user "Appuyez sur Entree une fois le repository cree..."
    success "Repository GitHub cree"
}

etape_8() {
    step "Etape 8/10 : Cloner le repository en local"
    save_progress 8

    # Charger les valeurs sauvegardées
    load_progress

    echo ""
    echo "Recuperons l'URL SSH de votre repository :"
    echo ""
    echo -e "${GRAY}  1. Sur la page de votre repository GitHub${NC}"
    echo -e "${GRAY}  2. Cliquez sur le bouton vert 'Code'${NC}"
    echo -e "${GRAY}  3. Selectionnez l'onglet 'SSH'${NC}"
    echo -e "${GRAY}  4. Copiez l'URL (format: git@github.com:username/repo.git)${NC}"
    echo ""

    # Boucle jusqu'à ce que le clone réussisse
    while true; do
        read -p "Collez l'URL SSH de votre repository : " REPO_URL

        if [ -z "$REPO_URL" ]; then
            warn "L'URL ne peut pas etre vide."
            continue
        fi

        # Valider le format de l'URL
        if [[ ! "$REPO_URL" =~ ^git@github\.com:.+/.+\.git$ ]]; then
            warn "L'URL ne semble pas etre au bon format."
            echo "Format attendu : git@github.com:username/repo.git"
            echo ""
            read -p "Voulez-vous reessayer ? (O/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                error "Etape passee. Vous devrez cloner manuellement."
                return 1
            fi
            continue
        fi

        substep "Clonage du repository..."

        cd ~
        mkdir -p Documents
        cd Documents

        # Extraire le nom du repo de l'URL
        REPO_NAME=$(basename "$REPO_URL" .git)

        if [ -d "$REPO_NAME" ]; then
            warn "Le dossier $REPO_NAME existe deja"
            read -p "Voulez-vous le supprimer et re-cloner ? (O/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                rm -rf "$REPO_NAME"
            else
                success "Utilisation du dossier existant"
                save_progress 8
                return 0
            fi
        fi

        echo ">> Clonage de $REPO_URL..."
        if git clone "$REPO_URL" 2>&1; then
            success "Repository clone dans ~/Documents/$REPO_NAME"
            save_progress 8
            return 0
        else
            error "Echec du clonage"
            echo ""
            echo "Causes possibles :"
            echo "  - L'URL est incorrecte"
            echo "  - Le repository n'existe pas"
            echo "  - La cle SSH n'est pas configuree sur GitHub"
            echo ""
            read -p "Voulez-vous reessayer avec une autre URL ? (O/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                error "Etape passee. Vous devrez cloner manuellement."
                return 1
            fi
        fi
    done
}

etape_9() {
    step "Etape 9/10 : Configuration de Supabase"
    save_progress 9

    manual_action "Vous devez creer un compte Supabase et un projet :

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
  8. Attendez ~2 minutes que le projet soit cree"

    open "https://supabase.com" 2>/dev/null || echo "Ouvrez manuellement : https://supabase.com"

    wait_for_user "Appuyez sur Entree une fois votre projet Supabase cree..."
    success "Projet Supabase cree"
}

etape_10() {
    step "Etape 10/10 : Connexion de Supabase a Claude Code (MCP)"
    save_progress 10

    # Charger les valeurs sauvegardées
    load_progress

    manual_action "Vous devez maintenant recuperer la commande MCP depuis Supabase :

  1. Dans votre projet Supabase, cliquez sur 'Connect' (en haut a droite)
  2. Cliquez sur l'onglet 'MCP'
  3. Selectionnez 'Claude Code'
  4. COPIEZ la commande affichee
     (elle ressemble a : claude mcp add --scope project ...)"

    wait_for_user "Appuyez sur Entree quand vous avez copie la commande MCP..."

    # Boucle jusqu'à ce que la commande MCP réussisse
    while true; do
        echo ""
        read -p "Collez la commande MCP ici : " MCP_COMMAND

        if [ -z "$MCP_COMMAND" ]; then
            warn "La commande ne peut pas etre vide."
            continue
        fi

        # Vérifier que c'est bien une commande claude mcp
        if [[ ! "$MCP_COMMAND" =~ ^claude[[:space:]]mcp ]]; then
            warn "Cette commande ne semble pas etre une commande MCP valide."
            echo "Elle devrait commencer par : claude mcp add ..."
            read -p "Voulez-vous reessayer ? (O/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                error "Etape passee. Vous devrez configurer MCP manuellement."
                break
            fi
            continue
        fi

        substep "Execution de la commande MCP dans votre projet..."

        # Aller dans le repo
        if [ -n "$REPO_NAME" ] && [ -d ~/Documents/"$REPO_NAME" ]; then
            cd ~/Documents/"$REPO_NAME"
        else
            warn "Dossier du projet non trouve, execution dans le dossier courant"
        fi

        if eval "$MCP_COMMAND" 2>&1; then
            success "MCP Supabase configure"
            break
        else
            error "Echec de la commande MCP"
            read -p "Voulez-vous reessayer ? (O/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                error "Etape passee. Vous devrez configurer MCP manuellement."
                break
            fi
        fi
    done

    manual_action "Derniere verification - Lancez Claude Code et verifiez MCP :

  1. Dans le Terminal, allez dans votre projet :
     cd ~/Documents/$REPO_NAME

  2. Lancez Claude Code :
     claude

  3. Tapez la commande :
     /mcp

  4. Appuyez sur Entree puis ACCEPTEZ la connexion
     quand Claude demande d'autoriser le serveur MCP Supabase

  5. Verifiez que 'supabase' apparait dans la liste des serveurs MCP"

    wait_for_user "Appuyez sur Entree une fois MCP verifie..."
    success "Supabase connecte a Claude Code"
}

show_completion() {
    # Supprimer le fichier de progression
    rm -f "$PROGRESS_FILE"

    echo ""
    echo -e "${GREEN}========================================"
    echo -e "  INSTALLATION TERMINEE AVEC SUCCES !"
    echo -e "========================================${NC}"
    echo ""
    echo "Resume de ce qui a ete installe et configure :"
    echo -e "  ${GREEN}[OK]${NC} Homebrew"
    echo -e "  ${GREEN}[OK]${NC} Node.js"
    echo -e "  ${GREEN}[OK]${NC} Git (avec votre identite)"
    echo -e "  ${GREEN}[OK]${NC} GitHub CLI"
    echo -e "  ${GREEN}[OK]${NC} Cle SSH (ajoutee a GitHub)"
    echo -e "  ${GREEN}[OK]${NC} Claude Code (connecte a votre compte)"
    echo -e "  ${GREEN}[OK]${NC} Repository GitHub (clone en local)"
    echo -e "  ${GREEN}[OK]${NC} Supabase (connecte via MCP)"
    echo ""
    echo -e "${YELLOW}Pour commencer a coder :${NC}"
    echo ""
    echo "  1. Ouvrez un nouveau Terminal"
    echo "  2. Allez dans votre projet :"
    echo -e "     ${CYAN}cd ~/Documents/$REPO_NAME${NC}"
    echo "  3. Lancez Claude Code :"
    echo -e "     ${CYAN}claude${NC}"
    echo "  4. Decrivez ce que vous voulez construire !"
    echo ""
    echo -e "${MAGENTA}Bon vibecoding ! ${NC}"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

# Traitement des arguments
START_STEP=0
SHOW_MENU=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --step|-s)
            START_STEP="$2"
            SHOW_MENU=false
            shift 2
            ;;
        --reset|-r)
            rm -f "$PROGRESS_FILE"
            echo "Progression reinitalisee."
            START_STEP=1
            SHOW_MENU=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --step, -s N   Commencer a l'etape N (1-10)"
            echo "  --reset, -r    Reinitialiser et recommencer depuis le debut"
            echo "  --help, -h     Afficher cette aide"
            echo ""
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Banner
clear
echo -e "${MAGENTA}"
cat << 'EOF'

 __     _____ ____  _____ ____ ___  ____ ___ _   _  ____
 \ \   / /_ _| __ )| ____/ ___/ _ \|  _ \_ _| \ | |/ ___|
  \ \ / / | ||  _ \|  _|| |  | | | | | | | ||  \| | |  _
   \ V /  | || |_) | |__| |__| |_| | |_| | || |\  | |_| |
    \_/  |___|____/|_____\____\___/|____/___|_| \_|\____|

           Setup Automatique macOS - v3.0

EOF
echo -e "${NC}"

echo "Ce script va vous guider pour installer tout le necessaire."
echo -e "${YELLOW}Certaines etapes necessitent des actions manuelles de votre part.${NC}"
echo -e "${GRAY}Duree estimee : 15-20 minutes${NC}"

# Afficher le menu ou utiliser l'argument
if $SHOW_MENU; then
    show_menu
fi

# Charger la progression existante
load_progress

# Exécuter les étapes
[ $START_STEP -le 1 ] && etape_1
[ $START_STEP -le 2 ] && etape_2
[ $START_STEP -le 3 ] && etape_3
[ $START_STEP -le 4 ] && etape_4
[ $START_STEP -le 5 ] && etape_5
[ $START_STEP -le 6 ] && etape_6
[ $START_STEP -le 7 ] && etape_7
[ $START_STEP -le 8 ] && etape_8
[ $START_STEP -le 9 ] && etape_9
[ $START_STEP -le 10 ] && etape_10

show_completion
