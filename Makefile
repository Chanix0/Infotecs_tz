SHELL := /bin/bash

# Путь к артефактам, относительно текущей директории
ARTIFACTS_DIR := $(CURDIR)/artifacts
DEB_DIR := /build/deb
DEB_PKG_NAME := nginx_$(REVISION)
REVISION := $(shell [[ -f history.log ]] && tail -n 1 history.log | awk '{print $$1+1}' || echo 1)

# Проверка наличия образа sandbox-ci
DOCKER_IMAGE := sandbox-ci 
DOCKER_EXISTS := $(shell docker images -q $(DOCKER_IMAGE))

# Функция для запуска контейнера
define run_in_docker
	docker run --rm -v $(SRC_DIR):/build/src -v $(ARTIFACTS_DIR):/build/artifacts -e CCACHE_DIR=/build/ccache $(DOCKER_IMAGE) bash -c "$(1)"
endef

# Проверка на наличие sandbox
sandbox:
	@if [ -z "$(DOCKER_EXISTS)" ]; then \
		echo "Собираем sandbox-контейнер..."; \
		docker build -t $(DOCKER_IMAGE) .; \
	fi

# Сборка Release с использованием strip для бинарника
build_release: sandbox
	@echo "Сборка Release (ревизия $(REVISION))"
	$(call run_in_docker, cd /build/src && ./auto/configure --with-http_ssl_module && make -j$(nproc) && strip /build/src/objs/nginx)
	@mkdir -p $(DEB_DIR)/DEBIAN
	@mkdir -p $(DEB_DIR)/usr/local/nginx/sbin
	@cp src/nginx/objs/nginx $(DEB_DIR)/usr/local/nginx/sbin/
	@echo "Package: nginx" > $(DEB_DIR)/DEBIAN/control
	@echo "Version: $(REVISION)" >> $(DEB_DIR)/DEBIAN/control
	@echo "Architecture: amd64" >> $(DEB_DIR)/DEBIAN/control
	@echo "Maintainer: <youremail@example.com>" >> $(DEB_DIR)/DEBIAN/control
	@echo "Description: Nginx web server" >> $(DEB_DIR)/DEBIAN/control
	@dpkg-deb --build $(DEB_DIR) $(ARTIFACTS_DIR)/$(DEB_PKG_NAME)$(REVISION)-release.deb
	@echo "$(REVISION) $(shell git rev-parse HEAD) release -" >> history.log

# Сборка Debug с отладочными символами
build_debug: sandbox
	@echo "Сборка Debug (ревизия $(REVISION))"
	$(call run_in_docker, cd /build/src && ./auto/configure --with-debug --with-http_ssl_module && make -j$(nproc))
	@mkdir -p $(DEB_DIR)/DEBIAN
	@mkdir -p $(DEB_DIR)/usr/local/nginx/sbin
	@cp src/nginx/objs/nginx $(DEB_DIR)/usr/local/nginx/sbin/
	@echo "Package: nginx" > $(DEB_DIR)/DEBIAN/control
	@echo "Version: $(REVISION)" >> $(DEB_DIR)/DEBIAN/control
	@echo "Architecture: amd64" >> $(DEB_DIR)/DEBIAN/control
	@echo "Maintainer: <youremail@example.com>" >> $(DEB_DIR)/DEBIAN/control
	@echo "Description: Nginx web server with debug symbols" >> $(DEB_DIR)/DEBIAN/control
	@dpkg-deb --build $(DEB_DIR) $(ARTIFACTS_DIR)/$(DEB_PKG_NAME)$(REVISION)-debug.deb
	@echo "$(REVISION) $(shell git rev-parse HEAD) debug -" >> history.log

# Сборка с покрытиями кода (gcov, lcov)
build_coverage: sandbox
	@echo "Сборка с покрытием кода (ревизия $(REVISION))"
	$(call run_in_docker, cd /build/src && ./auto/configure --with-debug --with-http_ssl_module --with-cc-opt="-fprofile-arcs -ftest-coverage" --with-ld-opt="-lgcov" && make -j$(nproc))
	$(call run_in_docker, cd /build/src && ./sbin/nginx --version && gcovr --xml -o coverage.xml)
	@mkdir -p $(DEB_DIR)/DEBIAN
	@mkdir -p $(DEB_DIR)/usr/local/nginx/sbin
	@cp src/nginx/objs/nginx $(DEB_DIR)/usr/local/nginx/sbin/
	@echo "Package: nginx" > $(DEB_DIR)/DEBIAN/control
	@echo "Version: $(REVISION)" >> $(DEB_DIR)/DEBIAN/control
	@echo "Architecture: amd64" >> $(DEB_DIR)/DEBIAN/control
	@echo "Maintainer: <youremail@example.com>" >> $(DEB_DIR)/DEBIAN/control
	@echo "Description: Nginx web server with coverage and debug symbols" >> $(DEB_DIR)/DEBIAN/control
	@dpkg-deb --build $(DEB_DIR) $(ARTIFACTS_DIR)/$(DEB_PKG_NAME)$(REVISION)-coverage.deb
	@cp /build/src/coverage.xml $(ARTIFACTS_DIR)/coverage_$(REVISION).xml
	@echo "$(REVISION) $(shell git rev-parse HEAD) coverage $(shell tail -n 1 $(ARTIFACTS_DIR)/coverage_$(REVISION).xml | grep -oP 'line-rate=\"\K[^\"]+')" >> history.log
	@python3 -c "import xml.etree.ElementTree as ET; tree = ET.parse('$(ARTIFACTS_DIR)/coverage_$(REVISION).xml'); root = tree.getroot(); line_rate = root.find('.//coverage').get('line-rate'); prev_line_rate = float(open('history.log').readlines()[-1].split()[6]); if float(line_rate) < prev_line_rate: exit(1)"

# Очистка
clean:
	rm -rf build artifacts history.log $(DEB_DIR)

.PHONY: sandbox build_release build_debug build_coverage clean