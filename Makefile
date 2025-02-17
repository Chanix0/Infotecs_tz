SHELL := /bin/bash

# Путь к артефактам, относительно текущей директории
ARTIFACTS_DIR := $(CURDIR)/artifacts
DEB_DIR := /build/deb
REVISION := $(shell [[ -f history.log ]] && tail -n 1 history.log | awk '{print $$1+1}' || echo 1)
DEB_PKG_NAME := nginx_$(REVISION)

# Проверка наличия образа sandbox-ci
DOCKER_IMAGE := $(notdir $(CURDIR))
DOCKER_EXISTS := $(shell docker images -q $(DOCKER_IMAGE))

# Функция для запуска контейнера
define run_in_docker
	docker run --rm -v $(SRC_DIR):/build/src -v $(ARTIFACTS_DIR):/build/artifacts -e CCACHE_DIR=/build/ccache $(DOCKER_IMAGE) bash -c "$(1)"
endef

# Функция для создания .deb пакета
define create_deb_package
	@mkdir -p $(DEB_DIR)/DEBIAN
	@mkdir -p $(DEB_DIR)/usr/sbin
	@cp  $(SRC_DIR)/objs/nginx $(DEB_DIR)/usr/sbin/
	@echo "Package: nginx" > $(DEB_DIR)/DEBIAN/control
	@echo "Version: $(REVISION)" >> $(DEB_DIR)/DEBIAN/control
	@echo "Architecture: amd64" >> $(DEB_DIR)/DEBIAN/control
	@echo "Maintainer: <sigma@venom.com>" >> $(DEB_DIR)/DEBIAN/control
	@echo "Description: $(1)" >> $(DEB_DIR)/DEBIAN/control
	@dpkg-deb --build $(DEB_DIR) $(ARTIFACTS_DIR)/$(DEB_PKG_NAME)-$(2).deb
endef

export create_deb_package

# Проверка на наличие sandbox
sandbox:
	@if [ -z "$(DOCKER_EXISTS)" ]; then \
		echo "Собираем sandbox-контейнер..."; \
		docker build -t $(DOCKER_IMAGE) .; \
	fi

# Сборка Release с использованием strip для бинаря
build_release: sandbox
	@echo "Сборка Release (ревизия $(REVISION))"
	$(call run_in_docker, cd /build/src && ./auto/configure --with-http_ssl_module && make -j$(nproc) && strip /build/src/objs/nginx)
	$(call create_deb_package, "Nginx web server",release)
	@echo "$(REVISION) release -" >> history.log

# Сборка Debug
build_debug: sandbox
	@echo "Сборка Debug (ревизия $(REVISION))"
	$(call run_in_docker, cd /build/src && ./auto/configure --with-debug --with-http_ssl_module && make -j$(nproc))
	$(call create_deb_package, "Nginx web server with debug symbols",debug)
	@echo "$(REVISION) debug -" >> history.log

#сборка с gcov/lcov
build_coverage: sandbox
	@echo "Сборка Coverage (ревизия $(REVISION))"
	$(call run_in_docker, cd /build/src && CCFLAGS='-fprofile-arcs -ftest-coverage' LDFLAGS='-fprofile-arcs -ftest-coverage -lgcov' ./auto/configure --with-http_ssl_module --with-cc-opt='-fprofile-arcs -ftest-coverage' --with-ld-opt='-lgcov' && make -j$(nproc)) 
	#Примитивный тест
	$(call run_in_docker, cd /build/src && /build/src/objs/nginx -V)
	
	#Генирируем отчет
	$(call run_in_docker, cd /build/src && lcov --capture --directory . --output-file coverage.info)
	$(call run_in_docker, cd /build/src && genhtml coverage.info --output-directory coverage_report)
cat 
	@mkdir -p $(ARTIFACTS_DIR)/coverage
	@cp -r $(SRC_DIR)/coverage_report $(ARTIFACTS_DIR)/coverage/$(REVISION)

	# Вычисление покрытия после генерации отчета, проверка покрытия, сборка deb если успешно
	@COVERAGE_LINES=$$(grep -oP '<td class="headerCovTableEntry">\K\d+' $(ARTIFACTS_DIR)/coverage/$(REVISION)/index.html | head -1);\
	LAST_COVERAGE=$$(tac history.log | awk '{if ($$2 == "coverage") {print $$NF; exit}}'); \
	echo "Текущее покрытие: $$COVERAGE_LINES, предыдущее: $$LAST_COVERAGE"; \
	if [ -n "$$LAST_COVERAGE" ] && [ `echo "$$COVERAGE_LINES > $$LAST_COVERAGE" | bc -l` -eq 1 ]; then \
		echo "Покрытие тестами увеличилось! Проверьте warnings в коде"; exit 1; \
	else \
		mkdir -p $(DEB_DIR)/DEBIAN; \
		mkdir -p $(DEB_DIR)/usr/sbin; \
		cp $(SRC_DIR)/objs/nginx $(DEB_DIR)/usr/sbin/; \
		echo "Package: nginx" > $(DEB_DIR)/DEBIAN/control; \
		echo "Version: $(REVISION)" >> $(DEB_DIR)/DEBIAN/control; \
		echo "Architecture: amd64" >> $(DEB_DIR)/DEBIAN/control; \
		echo "Maintainer: <sigma@venom.com>" >> $(DEB_DIR)/DEBIAN/control; \
		echo "Description: Nginx web server with coverage instrumentation" >> $(DEB_DIR)/DEBIAN/control; \
		dpkg-deb --build $(DEB_DIR) $(ARTIFACTS_DIR)/$(DEB_PKG_NAME)-coverage.deb; \
		echo "$(REVISION) coverage $$COVERAGE_LINES" >> history.log; \
	fi
	

# Очистка
clean:
	rm -rf build artifacts history.log $(DEB_DIR)

.PHONY: sandbox build_release build_debug build_coverage clean