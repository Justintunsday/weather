#pragma once

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cmath>
#include <string>

// A deliberately small, bounds-checked FlatBuffers reader/writer. It only
// supports tables, table vectors and scalar fields, which is all the WeatherKit
// response needs. Mutations are in-place: existing scalar fields keep their
// width and alignment, so the buffer never has to be rebuilt or resized.
class WSFlatBuffer {
public:
    WSFlatBuffer() : _data(nullptr), _size(0), _pos(0) {}
    WSFlatBuffer(uint8_t *data, size_t size, size_t pos) : _data(data), _size(size), _pos(pos) {}

    bool valid() const {
        if (!_data || _pos + 4 > _size) return false;
        int32_t soffset = readI32(_pos);
        int64_t vtable = (int64_t)_pos - (int64_t)soffset;
        if (vtable < 0 || vtable + 4 > (int64_t)_size) return false;
        uint16_t vtableLength = readU16((size_t)vtable);
        if (vtableLength < 4 || (vtableLength & 1) != 0) return false;
        if (vtable + vtableLength > (int64_t)_size) return false;
        uint16_t objectLength = readU16((size_t)vtable + 2);
        if (objectLength < 4 || _pos + objectLength > _size) return false;
        return true;
    }

    static WSFlatBuffer root(uint8_t *data, size_t size, bool *sizePrefixed) {
        if (sizePrefixed) *sizePrefixed = false;
        if (!data || size < 8) return WSFlatBuffer();
        uint32_t offset = readU32Static(data, 0);
        if (offset > 0 && offset < size) {
            WSFlatBuffer candidate(data, size, offset);
            if (candidate.valid()) return candidate;
        }
        offset = readU32Static(data, 4);
        if (offset > 0 && offset + 4 < size) {
            WSFlatBuffer candidate(data, size, 4 + offset);
            if (candidate.valid()) {
                if (sizePrefixed) *sizePrefixed = true;
                return candidate;
            }
        }
        return WSFlatBuffer();
    }

    bool fieldExists(int index) const { return fieldPointer(index, 0) != nullptr; }

    bool getU8(int index, uint8_t &value) const {
        const uint8_t *p = fieldPointer(index, 1);
        if (!p) return false;
        value = *p;
        return true;
    }

    bool getI8(int index, int8_t &value) const {
        uint8_t u = 0;
        if (!getU8(index, u)) return false;
        value = (int8_t)u;
        return true;
    }

    bool getI16(int index, int16_t &value) const {
        const uint8_t *p = fieldPointer(index, 2);
        if (!p) return false;
        value = (int16_t)readU16Static(p, 0);
        return true;
    }

    bool getI32(int index, int32_t &value) const {
        const uint8_t *p = fieldPointer(index, 4);
        if (!p) return false;
        value = (int32_t)readU32Static(p, 0);
        return true;
    }

    bool getF32(int index, float &value) const {
        const uint8_t *p = fieldPointer(index, 4);
        if (!p) return false;
        uint32_t bits = readU32Static(p, 0);
        std::memcpy(&value, &bits, sizeof(float));
        return true;
    }

    bool setU8(int index, uint8_t value) {
        uint8_t *p = mutableFieldPointer(index, 1);
        if (!p) return false;
        *p = value;
        return true;
    }

    bool setI8(int index, int8_t value) { return setU8(index, (uint8_t)value); }

    bool setI16(int index, int16_t value) {
        uint8_t *p = mutableFieldPointer(index, 2);
        if (!p) return false;
        p[0] = (uint8_t)((uint16_t)value & 0xff);
        p[1] = (uint8_t)(((uint16_t)value >> 8) & 0xff);
        return true;
    }

    bool setI32(int index, int32_t value) {
        uint8_t *p = mutableFieldPointer(index, 4);
        if (!p) return false;
        uint32_t u = (uint32_t)value;
        p[0] = (uint8_t)(u & 0xff);
        p[1] = (uint8_t)((u >> 8) & 0xff);
        p[2] = (uint8_t)((u >> 16) & 0xff);
        p[3] = (uint8_t)((u >> 24) & 0xff);
        return true;
    }

    bool setF32(int index, float value) {
        uint8_t *p = mutableFieldPointer(index, 4);
        if (!p) return false;
        uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(float));
        p[0] = (uint8_t)(bits & 0xff);
        p[1] = (uint8_t)((bits >> 8) & 0xff);
        p[2] = (uint8_t)((bits >> 16) & 0xff);
        p[3] = (uint8_t)((bits >> 24) & 0xff);
        return true;
    }

    WSFlatBuffer table(int index) const {
        const uint8_t *field = fieldPointer(index, 4);
        if (!field) return WSFlatBuffer();
        uint32_t offset = readU32Static(field, 0);
        size_t target = (size_t)(field - _data) + offset;
        if (target + 4 > _size) return WSFlatBuffer();
        WSFlatBuffer value(_data, _size, target);
        return value.valid() ? value : WSFlatBuffer();
    }

    bool vectorLength(int index, uint32_t &length) const {
        const uint8_t *field = fieldPointer(index, 4);
        if (!field) return false;
        size_t target = (size_t)(field - _data) + readU32Static(field, 0);
        if (target + 4 > _size) return false;
        uint32_t count = readU32Static(_data + target, 0);
        if (count > 100000) return false;
        if (target + 4 + (size_t)count * 4 > _size) return false;
        length = count;
        return true;
    }

    WSFlatBuffer vectorTable(int index, uint32_t element) const {
        const uint8_t *field = fieldPointer(index, 4);
        if (!field) return WSFlatBuffer();
        size_t vectorPos = (size_t)(field - _data) + readU32Static(field, 0);
        if (vectorPos + 4 > _size) return WSFlatBuffer();
        uint32_t count = readU32Static(_data + vectorPos, 0);
        if (element >= count || count > 100000) return WSFlatBuffer();
        size_t entryPos = vectorPos + 4 + (size_t)element * 4;
        if (entryPos + 4 > _size) return WSFlatBuffer();
        uint32_t offset = readU32Static(_data + entryPos, 0);
        size_t target = entryPos + offset;
        if (target + 4 > _size) return WSFlatBuffer();
        WSFlatBuffer value(_data, _size, target);
        return value.valid() ? value : WSFlatBuffer();
    }

    std::string stringValue(int index) const {
        const uint8_t *field = fieldPointer(index, 4);
        if (!field) return std::string();
        size_t target = (size_t)(field - _data) + readU32Static(field, 0);
        if (target + 4 > _size) return std::string();
        uint32_t length = readU32Static(_data + target, 0);
        if (length > 1024) return std::string();
        size_t start = target + 4;
        if (start + length > _size) return std::string();
        return std::string((const char *)(_data + start), length);
    }

    uint8_t *data() const { return _data; }
    size_t size() const { return _size; }

private:
    const uint8_t *fieldPointer(int index, size_t width) const {
        if (!valid() || index < 0) return nullptr;
        int32_t soffset = readI32(_pos);
        int64_t vtable = (int64_t)_pos - (int64_t)soffset;
        if (vtable < 0 || vtable + 4 > (int64_t)_size) return nullptr;
        uint16_t vtableLength = readU16((size_t)vtable);
        size_t entry = 4 + (size_t)index * 2;
        if (entry + 2 > vtableLength) return nullptr;
        uint16_t offset = readU16((size_t)vtable + entry);
        if (offset == 0) return nullptr;
        size_t field = _pos + offset;
        if (field + (width ? width : 4) > _size) return nullptr;
        return _data + field;
    }

    uint8_t *mutableFieldPointer(int index, size_t width) const {
        return const_cast<uint8_t *>(fieldPointer(index, width));
    }

    static uint16_t readU16Static(const uint8_t *data, size_t offset) {
        return (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    }

    static uint32_t readU32Static(const uint8_t *data, size_t offset) {
        return (uint32_t)data[offset] |
               ((uint32_t)data[offset + 1] << 8) |
               ((uint32_t)data[offset + 2] << 16) |
               ((uint32_t)data[offset + 3] << 24);
    }

    uint16_t readU16(size_t offset) const { return readU16Static(_data, offset); }
    uint32_t readU32(size_t offset) const { return readU32Static(_data, offset); }
    int32_t readI32(size_t offset) const { return (int32_t)readU32(offset); }

    uint8_t *_data;
    size_t _size;
    size_t _pos;
};

