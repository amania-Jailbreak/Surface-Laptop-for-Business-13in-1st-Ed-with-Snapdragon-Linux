// SPDX-License-Identifier: MIT

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#ifndef __user
#define __user
#endif

#include <drm/drm.h>
#include <drm/msm_drm.h>

struct param_query {
	const char *name;
	unsigned int id;
	int hexadecimal;
};

static int get_param(int fd, unsigned int id, uint64_t *value)
{
	struct drm_msm_param request = {
		.pipe = MSM_PIPE_3D0,
		.param = id,
	};

	if (ioctl(fd, DRM_IOCTL_MSM_GET_PARAM, &request) < 0)
		return -1;

	*value = request.value;
	return 0;
}

int main(void)
{
	static const struct param_query queries[] = {
		{ "GPU_ID", MSM_PARAM_GPU_ID, 0 },
		{ "CHIP_ID", MSM_PARAM_CHIP_ID, 1 },
		{ "GMEM_SIZE", MSM_PARAM_GMEM_SIZE, 0 },
		{ "GMEM_BASE", MSM_PARAM_GMEM_BASE, 1 },
		{ "MAX_FREQ", MSM_PARAM_MAX_FREQ, 0 },
		{ "PRIORITIES", MSM_PARAM_PRIORITIES, 0 },
		{ "VA_START", MSM_PARAM_VA_START, 1 },
		{ "VA_SIZE", MSM_PARAM_VA_SIZE, 1 },
		{ "HAS_PRR", MSM_PARAM_HAS_PRR, 0 },
	};
	char name[128] = { 0 };
	char date[128] = { 0 };
	char description[256] = { 0 };
	struct drm_version version = {
		.name_len = sizeof(name) - 1,
		.name = name,
		.date_len = sizeof(date) - 1,
		.date = date,
		.desc_len = sizeof(description) - 1,
		.desc = description,
	};
	int fd;
	int failures = 0;
	size_t i;

	fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "FAIL: open renderD128: %s\n", strerror(errno));
		return 1;
	}

	if (ioctl(fd, DRM_IOCTL_VERSION, &version) < 0) {
		fprintf(stderr, "FAIL: DRM_IOCTL_VERSION: %s\n", strerror(errno));
		close(fd);
		return 1;
	}

	printf("DRM driver: %s %d.%d.%d\n",
	       name, version.version_major, version.version_minor,
	       version.version_patchlevel);
	printf("Description: %s\n", description);
	printf("Date: %s\n", date);

	for (i = 0; i < sizeof(queries) / sizeof(queries[0]); i++) {
		uint64_t value;

		if (get_param(fd, queries[i].id, &value) < 0) {
			printf("%-12s ERROR: %s\n",
			       queries[i].name, strerror(errno));
			failures++;
			continue;
		}

		if (queries[i].hexadecimal)
			printf("%-12s 0x%" PRIx64 "\n",
			       queries[i].name, value);
		else
			printf("%-12s %" PRIu64 "\n",
			       queries[i].name, value);
	}

	close(fd);

	if (failures) {
		printf("GPU smoke test completed with %d query failure(s)\n",
		       failures);
		return 2;
	}

	printf("GPU smoke test passed\n");
	return 0;
}
