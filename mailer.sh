#!/bin/bash

# =======================================================
#  MAGIC MAILER: AUTO INSTALL + CONFIG + SEND
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
    exit 1
fi

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
  <p>Email ini dikirim dari server yang baru saja di-setup otomatis.</p>
  <ul>
    <li><b>Hostname:</b> $MY_HOSTNAME</li>
    <li><b>Status Installer:</b> Sukses</li>
    <li><b>Waktu:</b> $DATE_NOW</li>
  </ul>
  <hr>
  <small>Magic Mailer Script v2.0</small>
</body>
</html>
"
BODY_TEXT=$(echo "$BODY_HTML" | sed 's/<[^>]*>//g')

# --- 5. KIRIM EMAIL ---
echo "-------------------------------------------------"
echo "📨 Mengirim email ke: $TARGET_EMAIL"
echo "   Dari             : $SENDER_EMAIL"

(
cat <<EOF
From: "$SENDER_NAME" <$SENDER_EMAIL>
To: $TARGET_EMAIL
Reply-To: $REPLY_TO
Subject: $SUBJECT
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

# --- 6. LOGGING & DIAGNOSIS ---
if [ $? -eq 0 ]; then
    echo "✅ [SUKSES] Email sudah masuk antrian Postfix."
    echo "ℹ️  Cek status pengiriman dengan perintah: tail -n 10 /var/log/mail.log"
    
    # Cek koneksi port 25 ke Gmail (Diagnosis AWS)
    echo "🔍 Mendiagnosa jalur keluar (Port 25)..."
    timeout 3 bash -c "</dev/tcp/gmail-smtp-in.l.google.com/25" && echo "   -> Port 25 TERBUKA (Aman)." || echo "   -> ⚠️ Port 25 TERTUTUP/BLOKIR (Khas AWS/GCP). Anda perlu Request Open Port."
else
    echo "❌ [GAGAL] Terjadi kesalahan saat eksekusi sendmail."
fi
