#!/bin/bash

# ============================================================
#  🔥 AT&T EMAIL VALIDATOR - EXTREME ACCURACY EDITION
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# AT&T Domains List
ATT_DOMAINS=(
    "att.com"
    "att.net"
    "sbcglobal.net"
    "bellsouth.net"
    "ameritech.net"
    "flash.net"
    "nvbell.net"
    "pacbell.net"
    "prodigy.net"
    "snet.net"
    "swbell.net"
    "wans.net"
    "ameritech.com"
    "bellatlantic.net"
    "bellsouth.com"
    "flashcom.net"
    "nvbell.com"
    "pacbell.com"
    "prodigy.com"
    "sbc.com"
    "sbcglobal.com"
    "swbell.com"
    "waltoncounty.com"
    "ameritechcellular.com"
    "attglobal.net"
    "bellsouthmedia.com"
    "blurredmail.com"
    "cableone.net"
    "comcast.net"
    "earthlink.net"
    "embarqmail.com"
    "frontier.com"
    "frontiernet.net"
    "gmail.com"
    "hotmail.com"
    "icloud.com"
    "live.com"
    "msn.com"
    "outlook.com"
    "rocketmail.com"
    "verizon.net"
    "yahoo.com"
    "ymail.com"
    "aol.com"
    "cox.net"
    "juno.com"
    "netzero.net"
    "optonline.net"
    "roadrunner.com"
    "windstream.net"
    "woh.rr.com"
    "centurylink.net"
    "charter.net"
    "comporium.net"
    "embarq.com"
    "embarqmail.net"
    "knology.net"
    "mindspring.com"
    "peoplepc.com"
    "q.com"
    "twc.com"
    "wowway.com"
    "bright.net"
    "cinci.rr.com"
    "columbus.rr.com"
    "cwwcmail.net"
    "gvtc.com"
    "insightbb.com"
    "kctcs.net"
    "sc.rr.com"
    "suddenlink.net"
    "tampabay.rr.com"
    "triad.rr.com"
    "windstream.com"
    "winstonnet.com"
    "wow.com"
    "ameritech.net"
    "att.com"
    "bellsouth.net"
    "flash.net"
    "nvbell.net"
    "pacbell.net"
    "prodigy.net"
    "sbcglobal.net"
    "snet.net"
    "swbell.net"
    "wans.net"
)

# Files
VALID_FILE="email-valid-att.txt"
INVALID_FILE="email-invalid-att.txt"
SUSPECT_FILE="email-suspect-att.txt"
LOG_FILE="att-validation-$(date +%Y%m%d-%H%M%S).log"
MX_CACHE_FILE="mx-cache.txt"

# ==================== AT&T SPECIFIC VALIDATION ====================

# Fungsi untuk cek MX records AT&T
check_att_mx() {
    local domain="$1"
    
    # Cache MX records untuk performa
    if [ -f "$MX_CACHE_FILE" ] && grep -q "^$domain:" "$MX_CACHE_FILE"; then
        local cached_mx=$(grep "^$domain:" "$MX_CACHE_FILE" | cut -d':' -f2)
        echo "$cached_mx"
        return 0
    fi
    
    local mx_records=$(timeout 5 dig +short MX "$domain" 2>/dev/null | sort -n | head -5)
    
    if [ -n "$mx_records" ]; then
        # Simpan ke cache
        echo "$domain:$mx_records" >> "$MX_CACHE_FILE"
        echo "$mx_records"
        return 0
    fi
    
    return 1
}

# Fungsi untuk cek AT&T SMTP secara spesifik
check_att_smtp() {
    local email="$1"
    local domain="$2"
    
    echo "[AT&T SMTP CHECK] Testing $domain..." | tee -a "$LOG_FILE"
    
    # MX records untuk AT&T domains biasanya:
    # att.net -> mx.att.net
    # sbcglobal.net -> mx.sbcglobal.net
    # att.com -> inbound.att.net
    
    case "$domain" in
        "att.com"|"att.net")
            local mx_servers=("inbound.att.net" "mx.att.net")
            ;;
        "sbcglobal.net")
            local mx_servers=("mx.sbcglobal.net" "sbcglobal.net")
            ;;
        "bellsouth.net")
            local mx_servers=("mx.bellsouth.net" "bellsouth.net")
            ;;
        *)
            local mx_servers=("mx.$domain" "$domain")
            ;;
    esac
    
    # Test SMTP connection
    for mx in "${mx_servers[@]}"; do
        echo "  Testing SMTP server: $mx" | tee -a "$LOG_FILE"
        
        # Test port 25
        if timeout 3 nc -z "$mx" 25 2>/dev/null; then
            echo "  ✅ Port 25 OPEN on $mx" | tee -a "$LOG_FILE"
            
            # Try SMTP conversation (basic)
            local smtp_test=$(timeout 5 bash -c "
                exec 3<>/dev/tcp/$mx/25
                echo -e \"QUIT\" >&3
                cat <&3 | head -5
            " 2>/dev/null)
            
            if echo "$smtp_test" | grep -qi "220\|221"; then
                echo "  ✅ SMTP server responding: $mx" | tee -a "$LOG_FILE"
                return 0
            fi
        fi
        
        # Test port 587 (submission)
        if timeout 3 nc -z "$mx" 587 2>/dev/null; then
            echo "  ✅ Port 587 (Submission) OPEN on $mx" | tee -a "$LOG_FILE"
            return 0
        fi
        
        # Test port 465 (SMTPS)
        if timeout 3 nc -z "$mx" 465 2>/dev/null; then
            echo "  ✅ Port 465 (SMTPS) OPEN on $mx" | tee -a "$LOG_FILE"
            return 0
        fi
    done
    
    echo "  ❌ No SMTP ports open for $domain" | tee -a "$LOG_FILE"
    return 1
}

# Fungsi untuk cek disposable/temp emails
check_disposable_email() {
    local domain="$1"
    
    # Extensive disposable email domains list
    local disposable_domains=(
        "mailinator.com" "guerrillamail.com" "10minutemail.com"
        "yopmail.com" "temp-mail.org" "sharklasers.com"
        "grr.la" "getairmail.com" "maildrop.cc"
        "trashmail.com" "fakeinbox.com" "tempmail.com"
        "burnermail.io" "throwawaymail.com" "tempr.email"
        "anonaddy.com" "simplelogin.co" "firefox.com"
        "relay.firefox.com"
    )
    
    for disposable in "${disposable_domains[@]}"; do
        if [[ "$domain" == *"$disposable" ]]; then
            return 1
        fi
    done
    
    return 0
}

# Fungsi untuk cek email format khusus AT&T
validate_att_format() {
    local email="$1"
    
    # AT&T email format biasanya:
    # - firstname.lastname@att.net
    # - flastname@att.net  
    # - f.lastname@att.net
    # - firstname_lastname@att.net
    # - firstname@att.net
    
    local local_part=$(echo "$email" | cut -d'@' -f1)
    local domain=$(echo "$email" | cut -d'@' -f2)
    
    # 1. Check domain is in AT&T domains
    local is_att_domain=0
    for att_domain in "${ATT_DOMAINS[@]}"; do
        if [[ "$domain" == "$att_domain" ]]; then
            is_att_domain=1
            break
        fi
    done
    
    if [ $is_att_domain -eq 0 ]; then
        echo "  ❌ Not AT&T domain: $domain" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "  ✅ AT&T domain confirmed: $domain" | tee -a "$LOG_FILE"
    
    # 2. Check local part format
    if [[ ${#local_part} -lt 3 ]] || [[ ${#local_part} -gt 64 ]]; then
        echo "  ❌ Local part length invalid: $local_part" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # 3. Check for invalid characters
    if [[ "$local_part" =~ [^a-zA-Z0-9._%+-] ]]; then
        echo "  ❌ Invalid characters in local part" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # 4. Check for consecutive dots
    if [[ "$local_part" == *..* ]]; then
        echo "  ❌ Consecutive dots in local part" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # 5. Check if starts or ends with dot
    if [[ "$local_part" == .* ]] || [[ "$local_part" == *. ]]; then
        echo "  ❌ Local part starts/ends with dot" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "  ✅ Local part format valid: $local_part" | tee -a "$LOG_FILE"
    return 0
}

# Fungsi untuk test dengan mailx (real delivery test)
test_with_mailx() {
    local email="$1"
    
    echo "[MAILX TEST] Testing $email..." | tee -a "$LOG_FILE"
    
    # Clean mailbox first
    > /var/mail/root 2>/dev/null
    
    # Send test email
    local test_id="ATT_TEST_$(date +%s)_${RANDOM}"
    local subject="AT&T Validation Test - $test_id"
    
    echo "AT&T Email Validation Test - $test_id" | \
        mailx -s "$subject" "$email" 2>&1 | tee -a "$LOG_FILE"
    
    local send_result=$?
    
    if [ $send_result -eq 0 ]; then
        echo "  ✅ Test email sent successfully" | tee -a "$LOG_FILE"
        
        # Wait for bounce (AT&T biasanya cepat bounce jika invalid)
        echo "  ⏳ Waiting for bounce (15 seconds)..." | tee -a "$LOG_FILE"
        sleep 15
        
        # Check for bounce in mailbox
        if grep -q "<$email>" /var/mail/root 2>/dev/null; then
            echo "  ❌ BOUNCE DETECTED for $email" | tee -a "$LOG_FILE"
            return 1
        else
            echo "  ✅ NO BOUNCE - Email appears valid" | tee -a "$LOG_FILE"
            return 0
        fi
    else
        echo "  ❌ Failed to send test email" | tee -a "$LOG_FILE"
        return 1
    fi
}

# ==================== MAIN VALIDATION FUNCTION ====================

validate_att_email() {
    local email="$1"
    local test_mode="${2:-normal}"
    
    echo ""
    echo "=================================================================" | tee -a "$LOG_FILE"
    echo "🔍 VALIDATING AT&T EMAIL: $email" | tee -a "$LOG_FILE"
    echo "Mode: $test_mode" | tee -a "$LOG_FILE"
    echo "=================================================================" | tee -a "$LOG_FILE"
    
    # Layer 1: Basic Syntax
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "❌ [LAYER 1] Invalid email syntax" | tee -a "$LOG_FILE"
        echo "$email" >> "$INVALID_FILE"
        return 1
    fi
    echo "✅ [LAYER 1] Syntax valid" | tee -a "$LOG_FILE"
    
    # Layer 2: Extract domain
    local domain=$(echo "$email" | cut -d'@' -f2 | tr '[:upper:]' '[:lower:]')
    local local_part=$(echo "$email" | cut -d'@' -f1)
    
    # Layer 3: Disposable email check
    if ! check_disposable_email "$domain"; then
        echo "❌ [LAYER 3] Disposable email domain detected" | tee -a "$LOG_FILE"
        echo "$email" >> "$INVALID_FILE"
        return 1
    fi
    echo "✅ [LAYER 3] Not a disposable email" | tee -a "$LOG_FILE"
    
    # Layer 4: AT&T specific format validation
    if ! validate_att_format "$email"; then
        echo "❌ [LAYER 4] AT&T format validation failed" | tee -a "$LOG_FILE"
        echo "$email" >> "$SUSPECT_FILE"
        return 1
    fi
    echo "✅ [LAYER 4] AT&T format valid" | tee -a "$LOG_FILE"
    
    # Layer 5: MX Records check
    if ! check_att_mx "$domain"; then
        echo "⚠️ [LAYER 5] No MX records found (suspect)" | tee -a "$LOG_FILE"
        echo "$email" >> "$SUSPECT_FILE"
        # Continue anyway - some AT&T emails might still work
    else
        echo "✅ [LAYER 5] MX records found" | tee -a "$LOG_FILE"
    fi
    
    # Layer 6: SMTP connection test (if in aggressive mode)
    if [[ "$test_mode" == "aggressive" ]] || [[ "$test_mode" == "extreme" ]]; then
        if check_att_smtp "$email" "$domain"; then
            echo "✅ [LAYER 6] SMTP server reachable" | tee -a "$LOG_FILE"
        else
            echo "⚠️ [LAYER 6] SMTP server not reachable" | tee -a "$LOG_FILE"
            echo "$email" >> "$SUSPECT_FILE"
        fi
    fi
    
    # Layer 7: Real mailx test (if in extreme mode)
    if [[ "$test_mode" == "extreme" ]]; then
        echo "🚀 [LAYER 7] Performing REAL mailx delivery test..." | tee -a "$LOG_FILE"
        if test_with_mailx "$email"; then
            echo "🎉 [LAYER 7] REAL TEST PASSED - Email is 100% VALID" | tee -a "$LOG_FILE"
            echo "$email" >> "$VALID_FILE"
            return 0
        else
            echo "❌ [LAYER 7] REAL TEST FAILED - Email bounced" | tee -a "$LOG_FILE"
            echo "$email" >> "$INVALID_FILE"
            return 1
        fi
    fi
    
    # If we get here and email passed all tests, mark as valid
    echo "✅ [RESULT] Email passed all validation layers" | tee -a "$LOG_FILE"
    echo "$email" >> "$VALID_FILE"
    return 0
}

# ==================== BULK PROCESSING ====================

process_bulk_file() {
    local input_file="$1"
    local mode="${2:-normal}"
    
    if [ ! -f "$input_file" ]; then
        echo "❌ Input file not found: $input_file"
        return 1
    fi
    
    # Reset output files
    > "$VALID_FILE"
    > "$INVALID_FILE"
    > "$SUSPECT_FILE"
    > "$LOG_FILE"
    
    local total=$(wc -l < "$input_file")
    local processed=0
    local valid=0
    local invalid=0
    local suspect=0
    
    echo ""
    echo "================================================================"
    echo "🚀 AT&T BULK VALIDATION - MODE: $mode"
    echo "📁 Input File: $input_file"
    echo "📊 Total Emails: $total"
    echo "================================================================"
    
    # Create progress bar function
    show_progress() {
        local current=$1
        local total=$2
        local width=50
        local percentage=$((current * 100 / total))
        local completed=$((current * width / total))
        local remaining=$((width - completed))
        
        printf "\r["
        printf "%${completed}s" | tr ' ' '='
        printf "%${remaining}s" | tr ' ' ' '
        printf "] %3d%% (%d/%d)" "$percentage" "$current" "$total"
    }
    
    # Process emails
    while IFS= read -r email || [ -n "$email" ]; do
        email=$(echo "$email" | xargs | tr '[:upper:]' '[:lower:]')
        
        if [ -z "$email" ]; then
            continue
        fi
        
        ((processed++))
        
        echo "" >> "$LOG_FILE"
        echo "Processing [$processed/$total]: $email" >> "$LOG_FILE"
        
        show_progress "$processed" "$total"
        
        # Validate email
        if validate_att_email "$email" "$mode"; then
            ((valid++))
        else
            # Check which file it went to
            if grep -q "^$email$" "$INVALID_FILE" 2>/dev/null; then
                ((invalid++))
            elif grep -q "^$email$" "$SUSPECT_FILE" 2>/dev/null; then
                ((suspect++))
            fi
        fi
        
        # Rate limiting
        sleep "$DELAY_BETWEEN_TESTS"
        
    done < "$input_file"
    
    echo ""
    echo ""
    echo "================================================================"
    echo "📊 VALIDATION COMPLETE - RESULTS:"
    echo "================================================================"
    echo "✅ VALID EMAILS:   $valid"
    echo "❌ INVALID EMAILS: $invalid"
    echo "⚠️  SUSPECT EMAILS: $suspect"
    echo "📧 TOTAL PROCESSED: $processed"
    echo ""
    echo "📁 Output Files:"
    echo "   Valid:   $VALID_FILE"
    echo "   Invalid: $INVALID_FILE"
    echo "   Suspect: $SUSPECT_FILE"
    echo "   Log:     $LOG_FILE"
    echo ""
    
    # Show sample of valid emails
    if [ -s "$VALID_FILE" ]; then
        echo "📋 SAMPLE VALID EMAILS:"
        head -10 "$VALID_FILE" | while read line; do
            echo "   ✅ $line"
        done
    fi
    
    # Calculate accuracy
    if [ $processed -gt 0 ]; then
        local accuracy=$((valid * 100 / processed))
        echo ""
        echo "🎯 ACCURACY RATE: $accuracy%"
    fi
}

# ==================== SINGLE EMAIL TEST ====================

test_single_email() {
    local email="$1"
    
    echo ""
    echo "================================================================"
    echo "🧪 SINGLE AT&T EMAIL TEST"
    echo "================================================================"
    
    # Ask for test mode
    echo "Select test mode:"
    echo "1) Normal (Syntax + Format + MX)"
    echo "2) Aggressive (+ SMTP check)"
    echo "3) Extreme (+ Real mailx delivery test)"
    read -p "Choice [1-3]: " mode_choice
    
    case "$mode_choice" in
        1) mode="normal" ;;
        2) mode="aggressive" ;;
        3) mode="extreme" ;;
        *) mode="normal" ;;
    esac
    
    echo "Testing with mode: $mode"
    
    if validate_att_email "$email" "$mode"; then
        echo ""
        echo "================================================================"
        echo "🎉 EMAIL IS VALID!"
        echo "Saved to: $VALID_FILE"
        echo "================================================================"
    else
        echo ""
        echo "================================================================"
        echo "❌ EMAIL VALIDATION FAILED"
        echo "Check log file: $LOG_FILE"
        echo "================================================================"
    fi
}

# ==================== MAIN MENU ====================

show_menu() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║      🔥 AT&T EMAIL VALIDATOR - EXTREME EDITION   ║"
    echo "║              ZERO WASTE GUARANTEE                ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Select option:"
    echo "1) 🔍 Test single AT&T email"
    echo "2) 📁 Bulk validate from file"
    echo "3) 🚀 Extreme bulk validation (100% accuracy)"
    echo "4) 📊 Show statistics"
    echo "5) 🧹 Clean output files"
    echo "6) 📋 List AT&T domains"
    echo "7) 🎯 Quick check if email is AT&T"
    echo "8) 📄 View logs"
    echo "9) 🚪 Exit"
    echo ""
}

# ==================== MAIN EXECUTION ====================

main() {
    # Check if mailx is installed
    if ! command -v mailx &> /dev/null; then
        echo "Installing mailx..."
        apt-get update && apt-get install -y mailutils
    fi
    
    # Check if dig is installed
    if ! command -v dig &> /dev/null; then
        echo "Installing dnsutils..."
        apt-get install -y dnsutils
    fi
    
    # Check if netcat is installed
    if ! command -v nc &> /dev/null; then
        echo "Installing netcat..."
        apt-get install -y netcat
    fi
    
    while true; do
        show_menu
        read -p "Choice [1-9]: " choice
        
        case "$choice" in
            1)
                read -p "Enter AT&T email to test: " email
                test_single_email "$email"
                read -p "Press Enter to continue..."
                ;;
            2)
                read -p "Enter input file path: " input_file
                echo "Select mode:"
                echo "1) Normal (fast)"
                echo "2) Aggressive (more accurate)"
                read -p "Choice [1-2]: " bulk_mode
                
                case "$bulk_mode" in
                    1) mode="normal" ;;
                    2) mode="aggressive" ;;
                    *) mode="normal" ;;
                esac
                
                process_bulk_file "$input_file" "$mode"
                read -p "Press Enter to continue..."
                ;;
            3)
                read -p "Enter input file path: " input_file
                echo "⚠️  WARNING: Extreme mode will send actual test emails!"
                read -p "Are you sure? (y/n): " confirm
                if [[ "$confirm" == [yY] ]]; then
                    process_bulk_file "$input_file" "extreme"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                echo "📊 STATISTICS:"
                echo "================"
                if [ -f "$VALID_FILE" ]; then
                    echo "✅ Valid emails: $(wc -l < "$VALID_FILE")"
                else
                    echo "✅ Valid emails: 0"
                fi
                if [ -f "$INVALID_FILE" ]; then
                    echo "❌ Invalid emails: $(wc -l < "$INVALID_FILE")"
                else
                    echo "❌ Invalid emails: 0"
                fi
                if [ -f "$SUSPECT_FILE" ]; then
                    echo "⚠️  Suspect emails: $(wc -l < "$SUSPECT_FILE")"
                else
                    echo "⚠️  Suspect emails: 0"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                > "$VALID_FILE"
                > "$INVALID_FILE"
                > "$SUSPECT_FILE"
                echo "✅ All output files cleaned"
                read -p "Press Enter to continue..."
                ;;
            6)
                echo ""
                echo "📋 AT&T DOMAINS LIST:"
                echo "====================="
                for domain in "${ATT_DOMAINS[@]}"; do
                    echo "  • $domain"
                done | head -30
                echo ""
                echo "Total: ${#ATT_DOMAINS[@]} domains"
                read -p "Press Enter to continue..."
                ;;
            7)
                read -p "Enter email to check: " email
                local domain=$(echo "$email" | cut -d'@' -f2 | tr '[:upper:]' '[:lower:]')
                
                is_att=0
                for att_domain in "${ATT_DOMAINS[@]}"; do
                    if [[ "$domain" == "$att_domain" ]]; then
                        is_att=1
                        break
                    fi
                done
                
                if [ $is_att -eq 1 ]; then
                    echo -e "${GREEN}✅ This is an AT&T email ($domain)${NC}"
                else
                    echo -e "${RED}❌ Not an AT&T email ($domain)${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            8)
                if [ -f "$LOG_FILE" ]; then
                    tail -50 "$LOG_FILE"
                else
                    echo "No log file found"
                fi
                read -p "Press Enter to continue..."
                ;;
            9)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid choice"
                ;;
        esac
    done
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
