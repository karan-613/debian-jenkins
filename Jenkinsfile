pipeline {
  agent any
  options { timestamps(); buildDiscarder(logRotator(numToKeepStr: '20')); skipDefaultCheckout() }

  /***** 可按需修改的参数 *****/
  parameters {
    // 两个子 Job 名
    string(name: 'ENGINE_JOB',  defaultValue: 'uos-pulseaudio', description: 'pulseaudio 构建 Job 名称')
    string(name: 'SERVICE_JOB', defaultValue: 'uos-service',    description: 'service 构建 Job 名称')

    // 选择 “取哪个构建”的策略：lastSuccessful 或 指定构建号
    choice(name: 'ENGINE_SELECTOR',  choices: ['lastSuccessful','lastStable'], description: 'pulseaudio 制品选择器')
    choice(name: 'SERVICE_SELECTOR', choices: ['lastSuccessful','lastStable'], description: 'service 制品选择器')
    // 如果要指定构建号，可以新增参数 ENGINE_BUILD_NO / SERVICE_BUILD_NO 并在下面 selector 里改为 specific()

    // Debian 包相关
    string(name: 'PKG_NAME',     defaultValue: 'uos-audio',             description: '包名')
    string(name: 'PKG_VERSION',  defaultValue: '',                      description: '版本（留空则从 .so 文件名自动解析）')
    choice(name: 'DEB_ARCH',     choices: ['amd64','arm64'],            description: 'Debian 架构')
    string(name: 'PKGROOT',      defaultValue: 'driver',               description: '打包根目录（仓库内已有 DEBIAN/* 的那个目录）')

    // 产物要放入包内的目标路径（若你的 deb 仓库用自定义目录，只改这两项）
    string(name: 'DEST_SO_DIR',  defaultValue: 'usr/lib1', description: 'so 安装到 Deb 包内的目录（相对 PKGROOT）')
    string(name: 'DEST_SVC_DIR', defaultValue: 'usr/opt/elevoc/lib',                description: 'service 产物安装目录（相对 PKGROOT）')
  }

  environment {
    DIST_DIR = 'dist'     // 输出 .deb 的目录
  }

  stages {
    stage('Checkout packaging repo') {
      steps {
        deleteDir()
        checkout scm
        sh 'pwd && ls -al'
        sh '''
          test -d "${PKGROOT}/DEBIAN" || { echo "❌ 在仓库中找不到 ${PKGROOT}/DEBIAN，请确认 PKGROOT 参数与目录结构。"; exit 2; }
          mkdir -p "${DIST_DIR}"
          # 确保目标安装目录存在
          mkdir -p "${PKGROOT}/${DEST_SO_DIR}" "${PKGROOT}/${DEST_SVC_DIR}"
        '''
      }
    }

    stage('Fetch artifacts from children') {
      steps {
        script {
          // selector 选择器
          def selEngine  = params.ENGINE_SELECTOR == 'lastStable' ? lastStable()  : lastSuccessful()
          def selService = params.SERVICE_SELECTOR == 'lastStable' ? lastStable()  : lastSuccessful()

          // 从 pulseaudio Job 复制 *.so
          copyArtifacts projectName: params.ENGINE_JOB,
                        selector: selEngine,
                        filter: 'artifacts/*.so',
                        fingerprintArtifacts: true,
                        target: "${env.WORKSPACE}/pulseaudio_artifacts"

          // 从 service Job 复制全部 artifacts（按你那边归档的真实路径来，这里假设都在 artifacts/ 下）
          copyArtifacts projectName: params.SERVICE_JOB,
                        selector: selService,
                        filter: 'artifacts/**',
                        fingerprintArtifacts: true,
                        target: "${env.WORKSPACE}/service_artifacts"
        }
        sh '''
          echo "== Pulseaudio artifacts ==" && ls -al pulseaudio_artifacts || true
          echo "== Service artifacts =="    && ls -alR service_artifacts  || true
        '''
      }
    }

    stage('Place payloads into package tree') {
      steps {
        sh '''
          bash -euxo pipefail <<'BASH'
          SRC_PULSE="pulseaudio_artifacts/artifacts"
          SRC_SVC="service_artifacts/artifacts"

          # 复制 .so 到包内目录（按参数 DEST_SO_DIR）
          if ls "${SRC_PULSE}"/*.so >/dev/null 2>&1; then
            cp -v "${SRC_PULSE}"/*.so "${PKGROOT}/${DEST_SO_DIR}/"
          else
            echo "[warn] no pulseaudio *.so found; package may miss modules"
          fi

          # 复制 service 产物到包内目录（按参数 DEST_SVC_DIR）
          if [ -d "${SRC_SVC}" ] && [ "$(ls -A "${SRC_SVC}" 2>/dev/null)" ]; then
            # 文件
            find "${SRC_SVC}" -maxdepth 1 -type f -exec cp -v -t "${PKGROOT}/${DEST_SVC_DIR}/" {} +
            # 目录
            find "${SRC_SVC}" -maxdepth 1 -mindepth 1 -type d -exec cp -rv -t "${PKGROOT}/${DEST_SVC_DIR}/" {} +
          else
            echo "[warn] uos-service has no archived artifacts; skip"
          fi

          echo "== package tree preview =="
          ls -al "${PKGROOT}/${DEST_SO_DIR}"  || true
          ls -al "${PKGROOT}/${DEST_SVC_DIR}" || true
    BASH
        '''
      }
  }



    stage('Derive version from .so (optional)') {
      when { expression { return !params.PKG_VERSION?.trim() } }
      steps {
        script {
          def list = sh(
            script: 'ls pulseaudio_artifacts/artifacts/*.so 2>/dev/null | sed "s#.*/##"',
            returnStdout: true
          ).trim()
          def ver = ''
          if (list) {
            for (n in list.split("\\n")) {
              def m = (n =~ /module-(?:elevoc-engine|lock-default-sink)_[A-Za-z0-9]+_([0-9.]+)_[A-Za-z0-9]+\\.so/)
              if (m.find()) { ver = m.group(1); break }
            }
          }
          if (!ver) ver = '1.0.0'
          env.DEB_VER = ver
          echo "自动解析到版本：${ver}"
        }
      }
    }


    stage('Build .deb (dpkg-deb -b)') {
      steps {
        sh '''
          set -e
          VER="${PKG_VERSION:-${DEB_VER:-1.0.0}}"
          PKG="uos-audio"
          ARCH="amd64"

          # 目录 0755、文件默认 0644
          find driver -type d -print0 | xargs -0 -r chmod 0755
          find driver -type f -print0 | xargs -0 -r chmod 0644

          # 可执行放 0755（bin 下）
          if [ -d driver/usr/bin ]; then
            find driver/usr/bin -type f -print0 | xargs -0 -r chmod 0755
          fi
          # 若有其它需要可执行权限的文件也可在此处加

          # 维护脚本必须可执行（存在才改）
          for s in preinst postinst prerm postrm; do
            [ -f "driver/DEBIAN/$s" ] && chmod 0755 "driver/DEBIAN/$s" || true
          done

          OUT="dist/${PKG}_${VER}_${ARCH}.deb"
          echo "== 构建 Deb =="

          dpkg-deb -b driver "${OUT}"
          echo "产物: ${OUT}"
          ls -lh "${OUT}"
        '''
        archiveArtifacts artifacts: 'dist/*.deb', fingerprint: true
      }
    }
  }
  
}
