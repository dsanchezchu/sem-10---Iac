# Solución al Problema del Balanceador de Carga (Error 502)

## Resumen del Problema

El balanceador de carga de aplicación (ALB) devolvía un error 502 (Bad Gateway) al intentar acceder a los endpoints `/app1/health.html` y `/app1/`. Este error ocurría porque el servicio Nginx en la instancia app1 no se estaba instalando correctamente durante el aprovisionamiento.

## Infraestructura

La infraestructura está compuesta por:

- Un VPC con dos subredes públicas
- Dos instancias EC2 en Amazon Linux 2:
  - Una instancia con Nginx (app1) que recibe el 70% del tráfico
  - Una instancia con Apache (app2) que recibe el 30% del tráfico
- Un Application Load Balancer (ALB) que distribuye el tráfico
- Configuración de Target Groups para la verificación de salud de cada instancia

## Proceso de Diagnóstico

### 1. Verificación del estado de las instancias

Primero, verificamos que ambas instancias estaban ejecutándose correctamente:

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=*" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' --output table
```

Las instancias estaban en estado "running", pero al intentar una conexión directa a la instancia Nginx, no fue posible:

```bash
curl -I http://54.159.96.66/app1/health.html
# Resultado: Failed to connect to 54.159.96.66 port 80
```

### 2. Verificación del estado del Target Group

Verificamos el estado de salud del Target Group para la instancia Nginx:

```bash
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names app1-target-group --query 'TargetGroups[0].TargetGroupArn' --output text)
```

El resultado indicaba que la instancia estaba "unhealthy" debido a "Target.FailedHealthChecks".

### 3. Revisión de logs en la instancia

Al acceder a la instancia mediante SSH y revisar los logs de inicialización, identificamos el problema:

```bash
ssh -i ~/.ssh/app_key ec2-user@54.159.96.66 'sudo cat /var/log/user-data.log'
```

En los logs encontramos el error clave:

```
No package nginx1 available.
Error: Nothing to do
Failed to install Nginx
```

## Causa Raíz del Problema

**El script de inicialización (user data) intentaba instalar un paquete llamado "nginx1" que no existe.** 

La línea problemática en `main.tf` era:
```bash
sudo yum -y install nginx1
```

Aunque el repositorio "nginx1" se habilitaba correctamente con `amazon-linux-extras enable nginx1`, el nombre del paquete que debe instalarse es simplemente "nginx" (no "nginx1").

## Solución Implementada

### 1. Corrección del script de instalación

Modificamos el script en `main.tf` para usar el nombre correcto del paquete y agregamos diagnósticos adicionales:

```diff
- sudo yum -y install nginx1
+ echo "Installing nginx package (not nginx1)..."
+ sudo yum -y install nginx
```

También agregamos verificación y diagnóstico adicional:

```bash
# Verify nginx was installed correctly
echo "Verifying nginx installation..."
rpm -qa | grep nginx

# Verificación del estado del servicio
echo "Checking Nginx service status..."
sudo systemctl status nginx

# Verificación adicional de la configuración
echo "Checking health.html content and permissions:"
cat /usr/share/nginx/html/app1/health.html
ls -la /usr/share/nginx/html/app1/health.html
```

### 2. Ajuste de la configuración del health check

Modificamos la configuración del health check del Target Group para ser más tolerante durante la inicialización:

```bash
aws elbv2 modify-target-group \
  --target-group-arn $(aws elbv2 describe-target-groups --names app1-target-group --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --health-check-timeout-seconds 10
```

### 3. Reaprovisionamiento de la instancia

Terminamos la instancia anterior y aplicamos los cambios con Terraform:

```bash
aws ec2 terminate-instances --instance-ids i-0a9be1b2350e322a5
terraform apply
```

## Verificación de la Solución

Una vez implementados los cambios, verificamos que:

1. **El servicio Nginx se instaló correctamente:**
   ```bash
   ssh -i ~/.ssh/app_key ec2-user@13.218.202.57 'sudo systemctl status nginx'
   # Resultado: active (running)
   ```

2. **El endpoint de health check funciona localmente:**
   ```bash
   ssh -i ~/.ssh/app_key ec2-user@13.218.202.57 'curl -v http://localhost/app1/health.html'
   # Resultado: HTTP/1.1 200 OK, contenido: "OK"
   ```

3. **El endpoint es accesible directamente:**
   ```bash
   curl -v http://13.218.202.57/app1/health.html
   # Resultado: HTTP/1.1 200 OK, contenido: "OK"
   ```

4. **El Target Group muestra la instancia como saludable:**
   ```bash
   aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names app1-target-group --query 'TargetGroups[0].TargetGroupArn' --output text)
   # Resultado: "State": "healthy"
   ```

5. **El endpoint es accesible a través del balanceador de carga:**
   ```bash
   curl -v http://web-alb-633413710.us-east-1.elb.amazonaws.com/app1/health.html
   # Resultado: HTTP/1.1 200 OK, contenido: "OK"
   ```

## Lecciones Aprendidas

1. **Precisión en la nomenclatura de paquetes**: Es crucial usar el nombre exacto del paquete a instalar. En Amazon Linux 2, después de habilitar el repositorio "nginx1" con amazon-linux-extras, el paquete que debe instalarse se llama simplemente "nginx".

2. **Verificación de scripts de inicialización**: Siempre agregar comandos de verificación y diagnóstico en los scripts de inicialización para facilitar la resolución de problemas.

3. **Diagnóstico de health checks**: Es importante revisar los logs de acceso del servidor web para confirmar si los health checks del balanceador están llegando al servidor y qué respuestas están recibiendo.

4. **Ajuste de parámetros de health check**: A veces es necesario ajustar la configuración de los health checks para permitir un tiempo suficiente de inicialización, especialmente cuando hay instalación de software y configuración compleja.

5. **Importancia de los logs**: Los logs de user-data y de los servicios fueron cruciales para identificar y resolver el problema.

