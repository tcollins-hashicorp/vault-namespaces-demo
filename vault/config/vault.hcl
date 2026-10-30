# =============================================================================
# HashiCorp Vault Enterprise — Server Configuration
# =============================================================================

# Enable the Vault web UI
ui = true
disable_mlock = true   // set true here; IPC_LOCK cap_add handles OS locking

# Log format as JSON for structured ingestion
log_level  = "info"
log_format = "json"

# =============================================================================
# Storage Backend
# Integrated storage (Raft) — the recommended production backend, single node
# here for demo simplicity
# =============================================================================
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

# =============================================================================
# Listener — TCP (TLS disabled for demo convenience only)
# In production, always enable TLS with valid certificates
# =============================================================================
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# =============================================================================
# Cluster Addressing
# =============================================================================
api_addr     = "http://vault:8200"
cluster_addr = "https://vault:8201"
