#!/bin/bash

# =======================================================
#  MAGIC MAILER: AUTO INSTALL + CONFIG + SEND + VALIDATOR
# =======================================================

# --- 0. CEK PERIZINAN ROOT (Wajib untuk Install) ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Script ini harus dijalankan sebagai ROOT untuk bisa install aplikasi."
  echo "   Silakan ketik: sudo $0 <email_tujuan> <subjek>"
  exit 1
fi

# Input Argumen
TARGET_EMAIL="$1"
SUBJECT="${2:-Test Email dari Magic Script}"

if [[ -z "$TARGET_EMAIL" ]]; then
    echo "Usage: sudo ./magic_mailer.sh <email_tujuan> [subjek]"
    echo "       sudo ./magic_mailer.sh -f <file_mailist.txt> [subjek]"
    exit 1
fi

# --- FUNGSI VALIDASI EMAIL ---
validate_email() {
    local email="$1"
    
    # 1. Validasi format dasar
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "❌ Format email salah: $email"
        return 1
    fi
    
    # 2. Pisahkan domain
    local domain=$(echo "$email" | cut -d'@' -f2)
    
    # 3. Cek domain umum yang diblokir/placeholder
    local blocked_domains=("example.com" "test.com" "domain.com" "localhost" "test" "example")
    for blocked in "${blocked_domains[@]}"; do
        if [[ "$domain" == *"$blocked"* ]]; then
            echo "❌ Domain diblokir: $email"
            return 1
        fi
    done
    
    # 4. Cek MX record (opsional, bisa di-comment jika tidak perlu)
    if command -v dig &> /dev/null; then
        if ! dig +short MX "$domain" | grep -q "."; then
            echo "⚠️  Domain tidak memiliki MX record: $email"
            # Tetap return 0 karena beberapa email mungkin valid tanpa MX
        fi
    fi
    
    # 5. Simpan ke file email-valid.txt
    if ! grep -Fxq "$email" "email-valid.txt" 2>/dev/null; then
        echo "$email" >> "email-valid.txt"
        echo "✅ Email valid ditambahkan: $email"
    else
        echo "ℹ️  Email sudah ada di database: $email"
    fi
    
    return 0
}

# --- FUNGSI KIRIM EMAIL KE SATU ALAMAT ---
send_single_email() {
    local email="$1"
    local subject="$2"
    
    echo "-------------------------------------------------"
    echo "📨 Mengirim email ke: $email"
    echo "   Dari             : $SENDER_EMAIL"
    
    (
    cat <<EOF
From: "$SENDER_NAME" <$SENDER_EMAIL>
To: $email
Reply-To: $REPLY_TO
Subject: $subject
Date: $DATE_NOW
Message-ID: $MSG_ID
X-Mailer: Magic-Installer-Bash
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="$BOUNDARY"

--$BOUNDARY
Content-Type: text/plain; charset="utf-8"
Content-Transfer-Encoding: 7bit

$BODY_TEXT

--$BOUNDARY
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 7bit

$BODY_HTML

--$BOUNDARY--
EOF
    ) | /usr/sbin/sendmail -t
    
    return $?
}

# --- FUNGSI KIRIM KE BANYAK EMAIL DARI FILE ---
send_bulk_email() {
    local file="$1"
    local subject="$2"
    
    if [ ! -f "$file" ]; then
        echo "❌ File tidak ditemukan: $file"
        exit 1
    fi
    
    echo "================================================="
    echo "   📧 MEMULAI PENGIRIMAN BULK EMAIL"
    echo "================================================="
    echo "📋 File mailist: $file"
    echo "📝 Subjek      : $subject"
    echo "📊 Total email : $(wc -l < "$file")"
    echo "-------------------------------------------------"
    
    local count=0
    local success=0
    local failed=0
    
    # Buat file log
    LOG_FILE="email-send-$(date +%Y%m%d-%H%M%S).log"
    echo "Log pengiriman: $LOG_FILE"
    
    while IFS= read -r email || [ -n "$email" ]; do
        email=$(echo "$email" | xargs) # Trim whitespace
        if [ -z "$email" ]; then
            continue
        fi
        
        ((count++))
        
        echo -e "\n[$count] Memproses: $email"
        
        # Validasi email terlebih dahulu
        if validate_email "$email"; then
            # Kirim email
            if send_single_email "$email" "$subject"; then
                echo "   ✅ Berhasil dikirim"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS - $email" >> "$LOG_FILE"
                ((success++))
            else
                echo "   ❌ Gagal mengirim"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAILED - $email" >> "$LOG_FILE"
                ((failed++))
            fi
        else
            echo "   ⚠️  Email tidak valid, dilewati"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - INVALID - $email" >> "$LOG_FILE"
            ((failed++))
        fi
        
        # Delay antar pengiriman (optional)
        sleep 1
        
    done < "$file"
    
    echo "================================================="
    echo "   📊 LAPORAN AKHIR"
    echo "================================================="
    echo "✅ Berhasil dikirim : $success"
    echo "❌ Gagal            : $failed"
    echo "📧 Total diproses   : $count"
    echo "📝 Email valid disimpan di: email-valid.txt"
    echo "📋 Log lengkap di   : $LOG_FILE"
    echo "================================================="
}

# --- MAIN EXECUTION ---
echo "================================================="
echo "   🚀 MEMULAI PROSES PERSIAPAN SYSTEM & EMAIL    "
echo "================================================="

# --- 1. AUTO INSTALL DEPENDENCIES ---
install_dependencies() {
    if command -v sendmail &> /dev/null; then
        echo "✅ Sendmail/Postfix sudah terinstall."
    else
        echo "⚠️  Sendmail tidak ditemukan. Memulai instalasi otomatis..."
        
        # Deteksi OS
        if [ -f /etc/debian_version ]; then
            # UBUNTU/DEBIAN
            export DEBIAN_FRONTEND=noninteractive
            echo "   -> Mengupdate repository..."
            apt-get update -qq
            
            echo "   -> Mengonfigurasi Postfix (Internet Site)..."
            # Pre-seed konfigurasi agar tidak muncul layar ungu/biru
            echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
            echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections
            
            echo "   -> Menginstall Postfix & Mailutils..."
            apt-get install -y postfix mailutils openssl -qq
            
        elif [ -f /etc/redhat-release ]; then
            # CENTOS / AMAZON LINUX / RHEL
            echo "   -> Menginstall Postfix..."
            yum install -y postfix mailx openssl
            systemctl enable postfix
            systemctl start postfix
        else
            echo "❌ OS tidak didukung otomatis. Silakan install Postfix manual."
            exit 1
        fi
        echo "✅ Instalasi selesai."
    fi
}

install_dependencies

# --- 2. CEK & FIX HOSTNAME (PENTING BUAT AWS) ---
fix_hostname() {
    CURRENT_HOST=$(hostname -f)
    
    # Deteksi hostname default AWS/Cloud (biasanya mengandung ip-172, compute.internal, atau localhost)
    if [[ "$CURRENT_HOST" == *"compute.internal"* ]] || [[ "$CURRENT_HOST" == *"localhost"* ]] || [[ "$CURRENT_HOST" == *"ip-"* ]]; then
        echo "-------------------------------------------------"
        echo "⚠️  PERINGATAN: Hostname Anda saat ini buruk: '$CURRENT_HOST'"
        echo "    Email akan DITOLAK oleh Gmail jika menggunakan hostname ini."
        echo "-------------------------------------------------"
        read -p "👉 Masukkan Nama Domain/Subdomain Valid (misal: mail.mysite.com): " NEW_HOSTNAME
        
        if [[ -n "$NEW_HOSTNAME" ]]; then
            echo "   -> Mengubah hostname menjadi: $NEW_HOSTNAME"
            hostnamectl set-hostname "$NEW_HOSTNAME"
            
            # Update /etc/hosts agar tidak error sudo
            if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
                echo "127.0.0.1 $NEW_HOSTNAME" >> /etc/hosts
            fi
            
            # Refresh variable
            CURRENT_HOST="$NEW_HOSTNAME"
            
            # Restart postfix agar mengambil nama baru
            systemctl restart postfix
            echo "✅ Hostname diperbarui."
        else
            echo "⚠️  Hostname tidak diubah. Risiko masuk spam tinggi."
        fi
    fi
}

fix_hostname
MY_HOSTNAME=$(hostname -f)

# --- 3. KONFIGURASI PENGIRIM ---
SENDER_NAME="Admin Server"
SENDER_EMAIL="admin@$MY_HOSTNAME"
REPLY_TO="support@$MY_HOSTNAME"

# --- 4. GENERATE CONTENT (MIME) ---
BOUNDARY="MagicBound_$(date +%s)_$(openssl rand -hex 4)"
DATE_NOW=$(date -R)
MSG_ID="<$(date +%s).$(openssl rand -hex 4)@$MY_HOSTNAME>"

BODY_HTML="
<html>
<body>
  <h2>Halo!</h2>
  <p>Gracias</p>
</body>
</html>
"
BODY_TEXT=$(echo "$BODY_HTML" | sed 's/<[^>]*>//g')

# --- 5. CEK JIKA INPUT ADALAH FILE ---
if [[ "$TARGET_EMAIL" == "-f" ]] || [[ "$TARGET_EMAIL" == "--file" ]]; then
    MAIL_FILE="$2"
    CUSTOM_SUBJECT="${3:-$SUBJECT}"
    
    if [ -z "$MAIL_FILE" ]; then
        echo "Usage: sudo ./magic_mailer.sh -f <file_mailist.txt> [subjek]"
        exit 1
    fi
    
    # Kirim email ke banyak alamat dari file
    send_bulk_email "$MAIL_FILE" "$CUSTOM_SUBJECT"
    
else
    # Kirim email ke satu alamat
    echo "🔍 Validasi email: $TARGET_EMAIL"
    
    if validate_email "$TARGET_EMAIL"; then
        echo "✅ Email valid, melanjutkan pengiriman..."
        
        # Kirim email
        if send_single_email "$TARGET_EMAIL" "$SUBJECT"; then
            echo "✅ [SUKSES] Email sudah masuk antrian Postfix."
            echo "ℹ️  Cek status pengiriman dengan perintah: tail -n 10 /var/log/mail.log"
            
            # Cek koneksi port 25 ke Gmail (Diagnosis AWS)
            echo "🔍 Mendiagnosa jalur keluar (Port 25)..."
            timeout 3 bash -c "</dev/tcp/gmail-smtp-in.l.google.com/25" && echo "   -> Port 25 TERBUKA (Aman)." || echo "   -> ⚠️ Port 25 TERTUTUP/BLOKIR (Khas AWS/GCP). Anda perlu Request Open Port."
            
        else
            echo "❌ [GAGAL] Terjadi kesalahan saat eksekusi sendmail."
        fi
    else
        echo "❌ Email tidak valid, pengiriman dibatalkan."
        exit 1
    fi
fi

echo "================================================="
echo "   🎉 PROSES SELESAI"
echo "================================================="
echo "📁 Email valid tersimpan di: email-valid.txt"
echo "📋 Gunakan perintah berikut untuk melihat:"
echo "   cat email-valid.txt"
echo "   wc -l email-valid.txt"
echo "================================================="
