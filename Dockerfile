FROM teddysun/xray

# Copy the config file to the correct path for this image
COPY config.json /etc/xray/config.json

# Expose the port defined in config.json
EXPOSE 8080

# Run xray with the config file
CMD ["/usr/bin/xray", "-config", "/etc/xray/config.json"]

# join Telegram https://t.me/KS_GCP
# my username @ThaToeSaw
