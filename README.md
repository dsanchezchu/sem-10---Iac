# Infraestructura como Código - AWS Backup

Este repositorio contiene la configuración de Terraform para implementar una solución de respaldo automatizado en AWS.

## Archivos principales

- `main.tf`: Configuración principal de recursos
- `variables.tf`: Definición de variables
- `outputs.tf`: Outputs definidos del proyecto

## Requisitos

- Terraform instalado
- Credenciales de AWS configuradas
- Permisos necesarios en AWS para crear recursos de backup

## Uso

1. Inicializar Terraform:
```bash
terraform init
```

2. Revisar el plan:
```bash
terraform plan
```

3. Aplicar la configuración:
```bash
terraform apply
```
