# Proyecto GEM5

## 1. Requisitos

- Git
- Docker
- gem5 compilado con las configuraciones `ARM_MESI` y `ARM_MOESI_hammer`

## 2. Obtener el proyecto

Clonar el repositorio:

```bash
git clone git@github.com:Ahenao16/Proyecto-GEM5.git
cd Proyecto-GEM5
```

## 3. Construir la imagen Docker

Este paso se realiza una sola vez. La imagen incluye el compilador cruzado para ARM64.

```bash
sudo docker build -t proyecto-gem5 .
```

Si se modifica el `Dockerfile`, se vuelve a construir la imagen:

```bash
sudo docker build --no-cache -t proyecto-gem5 .
```

## 4. Iniciar el contenedor

Desde la carpeta del proyecto:

```bash
chmod +x scripts/enter-container.sh
./scripts/enter-container.sh
```

El contenedor tendrá acceso al proyecto en `/proyecto-gem5` y a los ejecutables de gem5 en `/gem5`.

## 5. Compilar el programa de prueba

El código fuente está en `src/hola.c`.

Dentro del contenedor, compilarlo como ejecutable estático para ARM64:

```bash
aarch64-linux-gnu-gcc -static \
  /proyecto-gem5/src/hola.c \
  -o /proyecto-gem5/src/hola
```

Comprobar que se generó el ejecutable:

```bash
file /proyecto-gem5/src/hola
```

## 6. Probar MESI_Two_Level

Ejecutar la simulación:

```bash
/gem5/build/ARM_MESI/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --cmd=/proyecto-gem5/src/hola
```

## 7. Probar MOESI_hammer

Ejecutar la misma prueba utilizando el otro ejecutable:

```bash
/gem5/build/ARM_MOESI_hammer/gem5.opt \
  /gem5/configs/deprecated/example/se.py \
  --cmd=/proyecto-gem5/src/hola
```


Esta prueba valida la ejecución básica.

## 9. Salir del contenedor

```bash
exit
```

El código fuente permanece en el equipo local. La imagen Docker conserva el compilador, por lo que no es necesario instalarlo en cada sesión.
