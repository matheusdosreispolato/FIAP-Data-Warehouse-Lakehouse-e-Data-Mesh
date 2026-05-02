variable "aws_region" {
  description = "Região AWS. Learner Lab permite apenas us-east-1 ou us-west-2."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "Learner Lab só permite us-east-1 ou us-west-2."
  }
}

variable "redshift_master_username" {
  description = "Usuário master do Redshift. Evite 'admin' (reservado em algumas versões)."
  type        = string
  default     = "dwadmin"
}

variable "redshift_master_password" {
  description = "Senha master do Redshift. Se vazio, o Terraform gera uma aleatória."
  type        = string
  default     = ""
  sensitive   = true
}

variable "redshift_node_type" {
  description = "Tipo de nó. Learner Lab só permite ra3.large."
  type        = string
  default     = "ra3.large"

  validation {
    condition     = var.redshift_node_type == "ra3.large"
    error_message = "Learner Lab restringe Redshift provisionado a ra3.large."
  }
}

variable "redshift_number_of_nodes" {
  description = "Quantidade de nós. Learner Lab permite no máximo 2. Usamos 1 para economizar budget."
  type        = number
  default     = 1

  validation {
    condition     = var.redshift_number_of_nodes >= 1 && var.redshift_number_of_nodes <= 2
    error_message = "Learner Lab permite no máximo 2 nós."
  }
}

variable "redshift_database_name" {
  description = "Nome do banco inicial criado no cluster."
  type        = string
  default     = "dw_mba"
}

variable "allowed_cidr_blocks" {
  description = "Lista de CIDRs que podem chegar ao Redshift. Padrão: 0.0.0.0/0 (laboratório). Em produção, restringir."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_public_access" {
  description = "Se true, cluster recebe IP público para Codespaces conectar. Laboratório: true. Produção: false."
  type        = bool
  default     = true
}
