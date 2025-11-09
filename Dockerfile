# Use the official V2Ray image
FROM v2fly/v2fly-core:v5.15.0

# Copy the config.json prepared by the script into the container
COPY config.json /etc/v2ray/config.json

# Expose port 8080 (which V2Ray will listen on, as per our config.json)
EXPOSE 8080

# Command to run V2Ray
CMD ["v2ray", "-config", "/etc/v2ray/config.json"]
