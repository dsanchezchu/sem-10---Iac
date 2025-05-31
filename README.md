# Infraestructura como Código - AWS Backup

Este repositorio contiene la configuración de Terraform para implementar una solución de respaldo automatizado en AWS y un balanceador de carga con distribución 70/30.

## Archivos principales

- `main.tf`: Configuración principal de recursos
- `variables.tf`: Definición de variables
- `outputs.tf`: Outputs definidos del proyecto

## Características

- Backup automatizado en AWS
- Balanceador de carga con distribución 70/30

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
