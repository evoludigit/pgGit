# pggit.dev Server Setup Guide

*Simple deployment setup for solo dev personal server*

## 🚀 Quick Deployment Steps

### 1. Configure the deployment script

Edit `deploy.sh` and update these values:
```bash
SERVER_USER="your-username"        # Your SSH username
SERVER_HOST="your-server.com"      # Your server hostname or IP
SERVER_PATH="/var/www/pggit.dev"   # Where to deploy the files
```

### 2. Set up the server directory

SSH into your server and create the web directory:
```bash
ssh your-username@your-server.com
sudo mkdir -p /var/www/pggit.dev
sudo chown $USER:$USER /var/www/pggit.dev
```

### 3. Configure Nginx

Copy the nginx config to your server:
```bash
# Copy the config file to your server
scp nginx-pggit.conf your-username@your-server.com:~/

# On your server, move it to nginx sites
sudo mv ~/nginx-pggit.conf /etc/nginx/sites-available/pggit.dev
sudo ln -s /etc/nginx/sites-available/pggit.dev /etc/nginx/sites-enabled/
```

### 4. Get SSL certificate (recommended)

```bash
# Install certbot if not already installed
sudo apt install certbot python3-certbot-nginx

# Get certificate for your domain
sudo certbot --nginx -d pggit.dev -d www.pggit.dev
```

### 5. Deploy!

From your local pggit directory:
```bash
./deploy.sh
```

## 🔧 Server Requirements

- **Nginx** (or Apache)
- **SSH access** with key-based authentication
- **Domain pointing to your server** (pggit.dev)
- **SSL certificate** (Let's Encrypt recommended)

## 📋 Checklist After Deployment

- [ ] Site loads at https://pggit.dev
- [ ] All pages work (test navigation)
- [ ] SSL certificate is valid
- [ ] Clean URLs work (no .html needed)
- [ ] Mobile responsiveness looks good
- [ ] Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`

## 🛠️ Troubleshooting

### Site not loading?
```bash
# Check nginx status
sudo systemctl status nginx

# Check nginx config
sudo nginx -t

# Restart nginx
sudo systemctl restart nginx
```

### SSL issues?
```bash
# Check certificate status
sudo certbot certificates

# Renew if needed
sudo certbot renew --dry-run
```

### Permission errors?
```bash
# Fix ownership
sudo chown -R www-data:www-data /var/www/pggit.dev

# Fix permissions
sudo chmod -R 755 /var/www/pggit.dev
```

## 🚀 Future Updates

To update the site:
1. Make changes to your docs
2. Run `./deploy.sh`
3. Changes are live immediately

## 💡 Pro Tips

- **Test locally first**: Use `python3 -m http.server 8000` in docs-web/
- **Monitor traffic**: Check nginx access logs regularly
- **Backup**: Your git repo IS your backup (keep it updated)
- **Performance**: The static site should be lightning fast

---

*This setup perfectly matches your solo dev, learning-in-public branding!*